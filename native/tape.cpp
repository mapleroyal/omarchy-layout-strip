// A narrow Lua bridge to Hyprland's public scrolling-layout API.
// No function hooks, private members, focus changes, or independent animations.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/layout/algorithm/Algorithm.hpp>
#include <hyprland/src/layout/algorithm/tiled/scrolling/ScrollingAlgorithm.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>

#include <lua.hpp>
#include <dlfcn.h>
#include <linux/input-event-codes.h>
#include <cmath>
#include <limits>
#include <stdexcept>
#include <string_view>

static HANDLE              g_handle = nullptr;
static CHyprSignalListener g_beforeDrop;
static CHyprSignalListener g_afterDrop;

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

static const char* panExact(Layout::Tiled::CScrollingAlgorithm* tape, double delta) {
    const auto column = tape->currentColumn();
    const auto data   = column ? column->scrollingData.lock() : nullptr;
    if (!data || !data->controller)
        return "exact pan requires a focused scrolling column";

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
    const int args = lua_gettop(lua);
    if ((args != 1 && args != 2) || lua_type(lua, 1) != LUA_TNUMBER || (args == 2 && lua_type(lua, 2) != LUA_TBOOLEAN))
        return result(lua, "pan expects a finite number in logical pixels and an optional exact-position boolean");

    const double delta = lua_tonumber(lua, 1);
    if (!std::isfinite(delta) || std::abs(delta) > std::numeric_limits<float>::max())
        return result(lua, "pan delta must be a finite representable number");

    const auto tape = currentTape();
    if (!tape)
        return result(lua, "no navigable scrolling tape on the focused monitor");

    if (tape->primaryViewportSize() <= 0)
        return result(lua, "scrolling viewport has no usable size");

    if (args == 2 && lua_toboolean(lua, 2))
        return result(lua, panExact(tape, delta));

    // Same public path as the stock scrolling gesture. Positive delta moves
    // content right and decreases the tape's camera offset. Recalculate uses
    // Hyprland's own window animations, with no forced warp.
    tape->moveTape(static_cast<float>(delta));
    return result(lua);
}

static int snapshot(lua_State* lua) {
    if (lua_gettop(lua) != 0)
        return result(lua, "snapshot expects no arguments");

    const auto tape = currentTape();
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
        !HyprlandAPI::addLuaFunction(handle, "tape", "info", info))
        throw std::runtime_error("native-tape: could not register hl.plugin.tape Lua API");

    g_beforeDrop = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent event, Event::SCallbackInfo&) { rememberLeadingDrop(event); });
    g_afterDrop  = Event::bus()->m_events.window.floating.listen([](PHLWINDOW window) { finishLeadingDrop(window); });

    return {"native-tape", "Public scrolling pan and geometry bridge for Lua", "mapleroyal", "1.2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_beforeDrop.reset();
    g_afterDrop.reset();
    g_pendingLeadingDrop.reset();
    g_dragOrigin.reset();
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "pan");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "snapshot");
    HyprlandAPI::removeLuaFunction(g_handle, "tape", "info");
}
