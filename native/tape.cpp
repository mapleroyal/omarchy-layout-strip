// A narrow Lua bridge to Hyprland's public scrolling-layout API.
// No function hooks, private members, focus changes, or independent animations.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <lua.hpp>
#include <dlfcn.h>
#include <linux/input-event-codes.h>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <unordered_map>
#include <set>
#include "Reorder.hpp"
#include "BarPressGuard.hpp"
#include "BarRegionRegistry.hpp"

static HANDLE              g_handle = nullptr;
static CHyprSignalListener g_beforeDrop;
static CHyprSignalListener g_afterDrop;
static CHyprSignalListener g_barPressListener;

using BarClock = std::chrono::steady_clock;
static TapeBarPress::RegionRegistry g_barRegions;
struct SBarPress {
    WP<Layout::Tiled::SScrollingData> data;
    PHLWORKSPACEREF workspace;
    PHLMONITORREF monitor;
    TapeBarPress::Lease<Layout::Tiled::SScrollInhibitor> lease;
    std::set<uint32_t> buttons;
    BarClock::time_point started;
};
static std::optional<SBarPress> g_barPress;
static wl_event_source* g_barReleaseIdle = nullptr;
static wl_event_source* g_barPressTimer = nullptr;

static void clearBarPress() {
    if (g_barReleaseIdle) {
        wl_event_source_remove(g_barReleaseIdle);
        g_barReleaseIdle = nullptr;
    }
    if (g_barPressTimer) {
        wl_event_source_remove(g_barPressTimer);
        g_barPressTimer = nullptr;
    }
    if (g_barPress) {
        const auto data = g_barPress->data.lock();
        if (data && data->controller)
            g_barPress->lease.restore(data->controller->getScrollInhibitor());
        g_barPress.reset();
    }
}

static void finishReleasedBarPress() {
    // During the release signal InputManager still reports the button held.
    // A Lua listener querying this bridge must not release protection before
    // later scrolling listeners run. After native input dispatch, it is safe.
    if (g_barPress && !g_pInputManager->hasHeldButtons())
        clearBarPress();
}

struct SPendingLeadingDrop {
    WP<Layout::ITarget>               target;
    WP<Layout::Tiled::SScrollingData> data;
    WP<Layout::Tiled::SColumnData>    first;
    size_t                            count = 0;
    float                             width = 0.F;
};
static std::optional<SPendingLeadingDrop> g_pendingLeadingDrop;
struct SDragOrigin {
    WP<Layout::ITarget> target;
    PHLWORKSPACEREF     workspace;
    PHLMONITORREF       monitor;
    float               width = 0.F;
};
static std::optional<SDragOrigin>          g_dragOrigin;

static Layout::Tiled::CScrollingAlgorithm* tapeForWorkspace(PHLWORKSPACE workspace) {
    if (!valid(workspace) || !workspace->m_space)
        return nullptr;

    const auto algorithm = workspace->m_space->algorithm();
    if (!algorithm || !algorithm->tiledAlgo())
        return nullptr;

    return dynamic_cast<Layout::Tiled::CScrollingAlgorithm*>(algorithm->tiledAlgo().get());
}

static Layout::Tiled::CScrollingAlgorithm* currentTape() {
    const auto focus = Desktop::focusState();
    if (!focus)
        return nullptr;

    const auto monitor = focus->monitor();
    if (!monitor)
        return nullptr;

    const auto workspace = monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace;
    if (!valid(workspace) || !workspace->m_space)
        return nullptr;

    const auto window = focus->window();
    if (window && (!window->m_isMapped || window->m_isFloating || window->m_workspace != workspace))
        return nullptr;

    // Real fullscreen is outside tape navigation. A full-width tiled column is
    // still an ordinary column and does not satisfy this check.
    if (Fullscreen::controller()->hasFullscreen(workspace))
        return nullptr;

    return tapeForWorkspace(workspace);
}

static int checkBarPress(void*) {
    if (!g_barPress)
        return 0;
    const auto workspace = g_barPress->workspace.lock();
    const auto monitor = g_barPress->monitor.lock();
    if (!g_pInputManager->hasHeldButtons() || !valid(workspace) || !monitor ||
        (monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace) != workspace ||
        g_barPress->data.expired() || BarClock::now() - g_barPress->started > std::chrono::minutes(2)) {
        clearBarPress();
        return 0;
    }
    wl_event_source_timer_update(g_barPressTimer, 100);
    return 0;
}

static void guardBarPress(IPointer::SButtonEvent event) {
    if (g_barPress) {
        if (event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            if (g_barReleaseIdle) {
                wl_event_source_remove(g_barReleaseIdle);
                g_barReleaseIdle = nullptr;
            }
            g_barPress->buttons.insert(event.button);
        } else {
            g_barPress->buttons.erase(event.button);
            if (g_barPress->buttons.empty() && !g_barReleaseIdle) {
                // Scrolling's RELEASE listener may precede or follow ours as
                // workspaces are created. Preserve inhibition until the entire
                // input signal finishes, before QML's later helper request.
                g_barReleaseIdle = wl_event_loop_add_idle(g_pCompositor->m_wlEventLoop, [](void*) {
                    g_barReleaseIdle = nullptr;
                    clearBarPress();
                }, nullptr);
            }
        }
        return;
    }
    if (event.state != WL_POINTER_BUTTON_STATE_PRESSED ||
        (g_layoutManager->dragController() && g_layoutManager->dragController()->target()))
        return;

    const auto pointerSurface = g_pSeatManager->m_state.pointerFocus.lock();
    if (!pointerSurface)
        return;
    const auto cursor = g_pInputManager->getMouseCoordsInternal();
    for (const auto& layer : Desktop::viewState()->layers()) {
        if (!layer->m_mapped || layer->resource() != pointerSurface ||
            (layer->m_namespace != "omarchy-bar" && layer->m_namespace != "omarchy-keyboard-panel" &&
             layer->m_namespace != "omarchy-keyboard-panel-dismiss"))
            continue;
        const auto monitor = layer->m_monitor.lock();
        if (!monitor)
            return;
        if (!g_barRegions.contains(monitor->m_name,cursor.x,cursor.y,BarClock::now()))
            return;
        // The release callback targets the OLD focused window, which can still
        // belong to another monitor while the pointer is over this bar. Its
        // offscreen logical box may extend across monitors, so protect its own
        // workspace, after authenticating the clicked strip above.
        const auto focused = Desktop::focusState()->window();
        if (!focused || !focused->m_isMapped || focused->m_isFloating)
            return;
        const auto workspace = focused->m_workspace;
        const auto focusedMonitor = valid(workspace) ? workspace->m_monitor.lock() : nullptr;
        const auto tape = tapeForWorkspace(workspace);
        if (!tape || !focusedMonitor || Fullscreen::controller()->hasFullscreen(workspace))
            return;
        const auto target = tape->dataFor(focused->layoutTarget());
        const auto column = target ? target->column.lock() : nullptr;
        const auto data = column ? column->scrollingData.lock() : nullptr;
        if (!data || !data->controller || data->controller->getScrollInhibitor().isInhibited)
            return;
        // A native watchdog handles cancelled/lost releases and dead workspaces;
        // it also guarantees no indefinite inhibition if the shell disappears.
        g_barPressTimer = wl_event_loop_add_timer(g_pCompositor->m_wlEventLoop, checkBarPress, nullptr);
        if (!g_barPressTimer)
            return;
        g_barPress.emplace();
        g_barPress->data = data;
        g_barPress->workspace = workspace;
        g_barPress->monitor = focusedMonitor;
        g_barPress->buttons.insert(event.button);
        g_barPress->started = BarClock::now();
        if (!g_barPress->lease.acquire(data->controller->getScrollInhibitor(), data->controller->getOffset())) {
            clearBarPress();
            return;
        }
        wl_event_source_timer_update(g_barPressTimer, 100);
        return;
    }
}

static void rememberLeadingDrop(IPointer::SButtonEvent event) {
    g_pendingLeadingDrop.reset();
    if (event.button == BTN_LEFT && event.state == WL_POINTER_BUTTON_STATE_PRESSED) {
        g_dragOrigin.reset();
        const auto cursor = g_pInputManager->getMouseCoordsInternal();
        const auto window = Desktop::viewState()->hitTest().windowAt(cursor, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);
        if (!window || window->m_isFloating || !window->m_isMapped)
            return;

        const auto target    = window->layoutTarget();
        const auto workspace = target ? target->workspace() : nullptr;
        const auto tape      = tapeForWorkspace(workspace);
        if (!tape || Fullscreen::controller()->hasFullscreen(workspace))
            return;

        const auto  targetData = tape->dataFor(target);
        const auto  column     = targetData ? targetData->column.lock() : nullptr;
        const float width      = column ? column->getColumnWidth() : 0.F;
        if (std::isfinite(width) && width > 0.F)
            g_dragOrigin = SDragOrigin{target, workspace, workspace->m_monitor, width};
        return;
    }
    if (event.button != BTN_LEFT || event.state != WL_POINTER_BUTTON_STATE_RELEASED || !g_layoutManager)
        return;

    const auto origin = g_dragOrigin;
    g_dragOrigin.reset();
    if (!origin)
        return;

    const auto& drag = g_layoutManager->dragController();
    if (!drag || drag->mode() != MBIND_MOVE || !drag->draggingTiled())
        return;

    const auto target = drag->target();
    const auto window = target ? target->window() : nullptr;
    if (!window || target != origin->target || !window->m_isMapped || !target->floating() || Desktop::focusState()->window() != window)
        return;

    const auto workspace = target->workspace();
    const auto monitor   = workspace ? workspace->m_monitor.lock() : nullptr;
    const auto tape      = tapeForWorkspace(workspace);
    if (!monitor || !tape || workspace != origin->workspace || monitor != origin->monitor || Fullscreen::controller()->hasFullscreen(workspace))
        return;

    const auto center = tape->getColumnAtViewportCenter();
    const auto data   = center ? center->scrollingData.lock() : nullptr;
    if (!data || data->columns.empty() || data->controller->getDirection() != Layout::Tiled::SCROLL_DIR_RIGHT)
        return;

    const auto first = data->columns.front();
    if (first->targetDatas.empty())
        return;

    const auto cursor = g_pInputManager->getMouseCoordsInternal();
    if (!monitor->logicalBox().containsPoint(cursor) || cursor.x > first->targetDatas.front()->layoutBox.x)
        return;

    // Match the native drop hit-test, which excludes the temporarily floating
    // dragged window. Only empty space before the first actual column qualifies.
    if (Desktop::viewState()->hitTest().windowAt(cursor, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS, window))
        return;

    g_pendingLeadingDrop = SPendingLeadingDrop{target, data, first, data->columns.size(), origin->width};
}

static void finishLeadingDrop(PHLWINDOW window) {
    if (!g_pendingLeadingDrop || !window || window->m_isFloating)
        return;

    const auto pending = *g_pendingLeadingDrop;
    g_pendingLeadingDrop.reset();
    const auto target = pending.target.lock();
    const auto data   = pending.data.lock();
    if (!target || target->window() != window || !data || !g_layoutManager || Desktop::focusState()->window() != window)
        return;

    const auto& drag = g_layoutManager->dragController();
    const auto  tape = tapeForWorkspace(target->workspace());
    if (!drag || !drag->wasDraggingWindow() || !drag->draggingTiled() || !tape || data->algorithm != tape)
        return;

    const auto moved  = tape->dataFor(target);
    const auto column = moved ? moved->column.lock() : nullptr;
    // Correct precisely the native no-hit append. Leave stacking, real target
    // drops, monitor transfers, and concurrent tape changes to native behavior.
    if (!column || data->columns.size() != pending.count + 1 || data->columns.front() != pending.first || data->columns.back() != column || column->targetDatas.size() != 1)
        return;

    column->setColumnWidth(pending.width);
    for (size_t i = 0; i < pending.count; ++i) {
        if (!tape->layoutMsg("swapcol l"))
            break;
    }
}

static int result(lua_State* lua, const char* error = nullptr) {
    lua_createtable(lua, 0, error ? 2 : 1);
    lua_pushboolean(lua, error == nullptr);
    lua_setfield(lua, -2, "ok");
    if (error) {
        lua_pushstring(lua, error);
        lua_setfield(lua, -2, "error");
    }
    return 1;
}

static void numberField(lua_State* lua, const char* name, double value) {
    lua_pushnumber(lua, value);
    lua_setfield(lua, -2, name);
}

static void boolField(lua_State* lua, const char* name, bool value) {
    lua_pushboolean(lua, value);
    lua_setfield(lua, -2, name);
}

static std::string_view stringArgument(lua_State* lua, int index) {
    size_t size = 0;
    const auto text = lua_tolstring(lua, index, &size);
    return {text, size};
}

static PHLMONITOR monitorNamed(std::string_view name) {
    for (const auto& monitor : State::monitorState()->monitors()) {
        if (monitor && monitor->m_name == name)
            return monitor;
    }
    return nullptr;
}

static Layout::Tiled::CScrollingAlgorithm* addressedTape(lua_State* lua, int workspaceIndex, int monitorIndex) {
    if (!lua_isinteger(lua, workspaceIndex) || lua_type(lua, monitorIndex) != LUA_TSTRING)
        return nullptr;
    const auto monitor = monitorNamed(stringArgument(lua, monitorIndex));
    if (!monitor)
        return nullptr;
    const auto workspace = monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace;
    if (!valid(workspace) || workspace->m_id != lua_tointeger(lua, workspaceIndex) || Fullscreen::controller()->hasFullscreen(workspace))
        return nullptr;
    return tapeForWorkspace(workspace);
}

static int protectBarRegion(lua_State* lua) {
    const int args = lua_gettop(lua);
    if ((args != 5 && args != 6) || lua_type(lua, 1) != LUA_TSTRING || lua_type(lua, 2) != LUA_TNUMBER ||
        lua_type(lua, 3) != LUA_TNUMBER || lua_type(lua, 4) != LUA_TNUMBER || lua_type(lua, 5) != LUA_TNUMBER ||
        (args == 6 && lua_type(lua, 6) != LUA_TSTRING))
        return result(lua, "protect_bar_region expects monitor, x, y, width, height and optional owner");
    const auto name = stringArgument(lua, 1);
    const auto owner = args == 6 ? stringArgument(lua, 6) : std::string_view{"legacy"};
    const TapeBarPress::Region bounds{lua_tonumber(lua, 2), lua_tonumber(lua, 3), lua_tonumber(lua, 4), lua_tonumber(lua, 5)};
    if (name.empty() || name.size() > 256 || name.find('\0') != std::string_view::npos || owner.empty() || owner.size() > 128 ||
        owner.find('\0') != std::string_view::npos || !std::isfinite(bounds.x) || !std::isfinite(bounds.y))
        return result(lua, "invalid layout-strip protection region or owner");
    if (bounds.width == 0 && bounds.height == 0) {
        g_barRegions.clear(name,owner); // A retiring instance cannot clear another owner's lease.
        return result(lua);
    }
    const auto monitor = monitorNamed(name);
    if (!bounds.valid() || !monitor)
        return result(lua, "invalid layout-strip protection region or missing monitor");
    const auto monitorBox = monitor->logicalBox();
    if (bounds.x < monitorBox.x - 1 || bounds.y < monitorBox.y - 1 || bounds.x + bounds.width > monitorBox.x + monitorBox.w + 1 ||
        bounds.y + bounds.height > monitorBox.y + monitorBox.h + 1)
        return result(lua, "layout-strip protection region is outside its monitor");
    if (!g_barRegions.refresh(name,owner,bounds,BarClock::now()))
        return result(lua, "too many layout-strip protection owners");
    return result(lua);
}

static PHLWINDOW windowAtAddress(std::string_view address) {
    if (!address.starts_with("0x") || address.size() <= 2)
        return nullptr;
    uintptr_t value = 0;
    const auto [end, error] = std::from_chars(address.data() + 2, address.data() + address.size(), value, 16);
    if (error != std::errc{} || end != address.data() + address.size())
        return nullptr;
    // Compare identities in the compositor-owned list. Never dereference a
    // caller-provided address, including an address from a stale bar snapshot.
    for (const auto& window : Desktop::viewState()->windows()) {
        if (reinterpret_cast<uintptr_t>(window.get()) == value)
            return window;
    }
    return nullptr;
}

static TapeReorder::Box reorderBox(const CBox& box) {
    return {box.x, box.y, box.w, box.h};
}

static int reorder(lua_State* lua) {
    finishReleasedBarPress();
    if (lua_gettop(lua) != 5 || lua_type(lua, 1) != LUA_TSTRING || lua_type(lua, 2) != LUA_TSTRING ||
        lua_type(lua, 3) != LUA_TSTRING || !lua_isinteger(lua, 4) || lua_type(lua, 5) != LUA_TSTRING)
        return result(lua, "reorder expects source address, target address, before/after, workspace integer, monitor name");

    const auto side = stringArgument(lua, 3);
    if (side != "before" && side != "after")
        return result(lua, "reorder side must be before or after");

    const auto sourceWindow = windowAtAddress(stringArgument(lua, 1));
    const auto targetWindow = windowAtAddress(stringArgument(lua, 2));
    const auto usableWindow = [](const PHLWINDOW& window) {
        return window && window->m_isMapped && !window->isHidden() && !window->m_isFloating && valid(window->m_workspace);
    };
    if (!usableWindow(sourceWindow) || !usableWindow(targetWindow))
        return result(lua, "the source or target is no longer a visible tiled window");

    const auto workspace = sourceWindow->m_workspace;
    const auto monitor = workspace->m_monitor.lock();
    if (targetWindow->m_workspace != workspace || workspace->m_id != lua_tointeger(lua, 4) || !monitor ||
        monitor->m_name != stringArgument(lua, 5) ||
        (monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace) != workspace)
        return result(lua, "the displayed workspace or monitor changed");

    if (Fullscreen::controller()->hasFullscreen(workspace))
        return result(lua, "cannot reorder a workspace with a real fullscreen window");
    const auto& drag = g_layoutManager->dragController();
    if (drag && drag->target())
        return result(lua, "cannot reorder during a native window drag");

    // Address the requested workspace directly; keyboard focus may belong to a
    // floating window, another monitor, or an entirely different workspace.
    const auto tape = tapeForWorkspace(workspace);
    if (!tape)
        return result(lua, "the workspace is no longer using the scrolling layout");
    const auto sourceData = tape->dataFor(sourceWindow->layoutTarget());
    const auto targetData = tape->dataFor(targetWindow->layoutTarget());
    const auto source = sourceData ? sourceData->column.lock() : nullptr;
    const auto target = targetData ? targetData->column.lock() : nullptr;
    const auto data = source ? source->scrollingData.lock() : nullptr;
    if (!source || !target || !data || data->algorithm != tape || target->scrollingData.lock() != data || !data->controller)
        return result(lua, "the source or target scrolling column changed");
    const auto sourceIndex = data->idx(source);
    const auto targetIndex = data->idx(target);
    if (sourceIndex < 0 || targetIndex < 0 || data->controller->stripCount() != data->columns.size())
        return result(lua, "the scrolling columns are changing");

    auto& inhibitor = data->controller->getScrollInhibitor();
    if (inhibitor.isInhibited)
        return result(lua, "cannot reorder while another operation inhibits scrolling");

    const auto area = tape->usableArea();
    const double viewport = tape->primaryViewportSize();
    const double offsetBefore = data->controller->getOffset();
    std::optional<size_t> focusedIndex;
    const auto focused = Desktop::focusState()->window();
    if (focused && focused->m_workspace == workspace && !focused->m_isFloating) {
        const auto focusedData = tape->dataFor(focused->layoutTarget());
        const auto focusedColumn = focusedData ? focusedData->column.lock() : nullptr;
        const auto index = focusedColumn ? data->idx(focusedColumn) : -1;
        if (index >= 0)
            focusedIndex = static_cast<size_t>(index);
    }

    TapeReorder::Plan plan;
    try {
        std::vector<double> widths;
        widths.reserve(data->columns.size());
        for (size_t i = 0; i < data->columns.size(); ++i) {
            if (data->controller->getStrip(i).userData.lock() != data->columns[i])
                return result(lua, "the scrolling strip identities changed");
            widths.push_back(data->controller->calculateStripSize(i, area));
        }
        plan = TapeReorder::plan(widths, viewport, offsetBefore, sourceIndex, targetIndex, side == "after", focusedIndex);
    } catch (const std::exception& error) {
        return result(lua, error.what());
    }

    const bool changed = plan.destination != static_cast<size_t>(sourceIndex);
    size_t suppressedAnimations = 0;
    if (changed) {
        struct SPreviousTarget {
            SP<Layout::ITarget> target;
            TapeReorder::Box goal;
            TapeReorder::Box current;
        };
        std::vector<SPreviousTarget> previousTargets;
        for (const auto& column : data->columns) {
            for (const auto& targetData : column->targetDatas) {
                const auto item = targetData->target.lock();
                if (!item)
                    continue;
                const auto representative = item->window();
                const auto goal = item->position();
                const auto current = representative ? representative->geometricBox(Desktop::View::IGeometric::GEOMETRIC_CURRENT) : goal;
                previousTargets.push_back({item, reorderBox(goal), reorderBox(current)});
            }
        }

        // Native swapcol makes these same two swaps, then focuses its camera on
        // the active column after every step. Here the source is addressed and
        // the camera policy is applied once. No focus, activation, MRU, pointer,
        // workspace or monitor mutations are involved.
        size_t current = static_cast<size_t>(sourceIndex);
        while (current != plan.destination) {
            const size_t next = current < plan.destination ? current + 1 : current - 1;
            std::swap(data->columns[current], data->columns[next]);
            data->controller->swapStrips(current, next);
            current = next;
        }

        // Preserve the chosen camera even for a deliberately half-placed short
        // tape. Restore the inhibitor before any Lua allocations/callbacks.
        struct SRestoreInhibitor {
            Layout::Tiled::SScrollInhibitor& target;
            Layout::Tiled::SScrollInhibitor saved;
            ~SRestoreInhibitor() { target = saved; }
        } restore{inhibitor, inhibitor};
        inhibitor.isInhibited = true;
        inhibitor.offsetWhenInhibited = plan.offset;
        data->controller->setOffset(plan.offset);
        data->recalculate();

        const auto monitorBox = reorderBox(monitor->logicalBox());
        for (const auto& previous : previousTargets) {
            if (TapeReorder::suppressOffscreenAnimation(previous.goal, previous.current,
                                                       reorderBox(previous.target->position()), monitorBox)) {
                // A left-offscreen to right-offscreen move must not sweep across
                // the user's visible apps. Finish only the invisible targets'
                // native geometry animation; visible targets animate normally.
                previous.target->warpPositionSize();
                ++suppressedAnimations;
            }
        }
    }

    result(lua);
    boolField(lua, "changed", changed);
    boolField(lua, "anchorPreserved", plan.anchorPreserved);
    numberField(lua, "sourceIndex", sourceIndex);
    numberField(lua, "targetIndex", plan.destination);
    numberField(lua, "offsetBefore", offsetBefore);
    numberField(lua, "offsetAfter", data->controller->getOffset());
    numberField(lua, "suppressedAnimations", suppressedAnimations);
    return 1;
}

static const char* panExact(Layout::Tiled::CScrollingAlgorithm* tape, double delta) {
    const auto column = tape->getColumnAtViewportCenter();
    const auto data   = column ? column->scrollingData.lock() : nullptr;
    if (!data || !data->controller)
        return "exact pan requires a scrolling column";

    auto& inhibitor = data->controller->getScrollInhibitor();
    if (inhibitor.isInhibited)
        return "exact pan cannot replace an existing scroll inhibitor";

    // Explicit half placement can intentionally leave blank space. The native
    // controller otherwise centers any tape shorter than the viewport. Preserve
    // this one requested offset while recalculating, then restore native policy.
    // The scope contains no Lua calls, so a Lua error cannot strand the inhibitor.
    struct SRestoreInhibitor {
        Layout::Tiled::SScrollInhibitor& target;
        Layout::Tiled::SScrollInhibitor  saved;
        ~SRestoreInhibitor() {
            target = saved;
        }
    } restore{inhibitor, inhibitor};

    const double desired          = data->controller->getOffset() - delta;
    inhibitor.isInhibited         = true;
    inhibitor.offsetWhenInhibited = desired;
    // moveTape(0) skips recalc, but an explicit placement still needs the native
    // layout to apply the selected offset, even when it is already the goal.
    if (delta == 0.0)
        data->recalculate();
    else
        tape->moveTape(static_cast<float>(delta));
    return nullptr;
}

static int pan(lua_State* lua) {
    finishReleasedBarPress();
    const int args = lua_gettop(lua);
    if ((args != 1 && args != 2 && args != 4) || lua_type(lua, 1) != LUA_TNUMBER ||
        (args >= 2 && lua_type(lua, 2) != LUA_TBOOLEAN) || (args == 4 && (!lua_isinteger(lua, 3) || lua_type(lua, 4) != LUA_TSTRING)))
        return result(lua, "pan expects delta, optional exact boolean, and optional workspace integer + monitor name");

    const double delta = lua_tonumber(lua, 1);
    if (!std::isfinite(delta) || std::abs(delta) > std::numeric_limits<float>::max())
        return result(lua, "pan delta must be a finite representable number");

    const auto tape = args == 4 ? addressedTape(lua, 3, 4) : currentTape();
    if (!tape)
        return result(lua, "the requested scrolling workspace is unavailable or fullscreen");
    if (const auto& drag = g_layoutManager->dragController(); drag && drag->target())
        return result(lua, "cannot pan during a native window drag");

    if (tape->primaryViewportSize() <= 0)
        return result(lua, "scrolling viewport has no usable size");
    if (args == 4) {
        const auto column = tape->getColumnAtViewportCenter();
        const auto data = column ? column->scrollingData.lock() : nullptr;
        if (!data || !data->controller || data->controller->getScrollInhibitor().isInhibited)
            return result(lua, "addressed pan cannot replace another scrolling operation");
    }

    if (args >= 2 && lua_toboolean(lua, 2))
        return result(lua, panExact(tape, delta));

    // Same public path as the stock scrolling gesture. Positive delta moves
    // content right and decreases the tape's camera offset. Recalculate uses
    // Hyprland's own window animations, with no forced warp.
    tape->moveTape(static_cast<float>(delta));
    return result(lua);
}

static int snapshot(lua_State* lua) {
    finishReleasedBarPress();
    const int args = lua_gettop(lua);
    if (args != 0 && (args != 2 || !lua_isinteger(lua, 1) || lua_type(lua, 2) != LUA_TSTRING))
        return result(lua, "snapshot expects no arguments or a workspace integer and monitor name");

    const auto tape = args == 2 ? addressedTape(lua, 1, 2) : currentTape();
    if (!tape)
        return result(lua, "no navigable scrolling tape on the focused monitor");

    const double width = tape->primaryViewportSize();
    const auto   area  = tape->usableArea();
    result(lua);
    numberField(lua, "offset", tape->normalizedTapeOffset() * width);
    numberField(lua, "width", width);
    numberField(lua, "x", area.x);
    numberField(lua, "y", area.y);
    numberField(lua, "height", area.h);
    return 1;
}

static int info(lua_State* lua) {
    if (lua_gettop(lua) != 0)
        return result(lua, "info expects no arguments");

    Dl_info library{};
    if (!dladdr(reinterpret_cast<void*>(&info), &library) || !library.dli_fname)
        return result(lua, "could not resolve native tape library path");

    result(lua);
    lua_pushstring(lua, library.dli_fname);
    lua_setfield(lua, -2, "path");
    lua_pushstring(lua, GIT_COMMIT_HASH);
    lua_setfield(lua, -2, "git_hash");
    numberField(lua, "protocolVersion", 2);
    boolField(lua, "addressedCamera", true);
    boolField(lua, "ownedRegions", true);
    numberField(lua, "protectedRegionCount", g_barRegions.count(BarClock::now()));
    boolField(lua, "reorder", true);
    return 1;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    // C++ plugin ABI changes with Hyprland and its supporting libraries. Refuse
    // to load until rebuilt against the headers matching the running version.
    if (std::string_view(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash() || HyprlandAPI::getHyprlandVersion(handle).hash != GIT_COMMIT_HASH)
        throw std::runtime_error("native-tape: Hyprland ABI mismatch; rebuild the plugin against the running version");

    g_handle = handle;
    if (!HyprlandAPI::addLuaFunction(handle, "tape", "pan", pan) || !HyprlandAPI::addLuaFunction(handle, "tape", "snapshot", snapshot) ||
        !HyprlandAPI::addLuaFunction(handle, "tape", "reorder", reorder) ||
        !HyprlandAPI::addLuaFunction(handle, "tape", "protect_bar_region", protectBarRegion) ||
        !HyprlandAPI::addLuaFunction(handle, "tape", "info", info))
        throw std::runtime_error("native-tape: could not register hl.plugin.tape Lua API");

    g_beforeDrop = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) { rememberLeadingDrop(event); });
    g_afterDrop  = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) { finishLeadingDrop(window); });
    g_barPressListener = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) { guardBarPress(event); });

    return {"native-tape", "Public scrolling navigation and addressed reorder bridge for Lua", "local", "2.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_beforeDrop.reset();
    g_afterDrop.reset();
    g_barPressListener.reset();
    clearBarPress();
    g_barRegions.clearAll();
    g_pendingLeadingDrop.reset();
    g_dragOrigin.reset();
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "pan");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "snapshot");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "reorder");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "protect_bar_region");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "info");
}
