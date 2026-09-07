# Native tape bridge

This local Hyprland plugin exposes the following functions to Lua:

- `hl.plugin.tape.pan(delta)` moves the native tape by `delta` logical pixels.
  Positive deltas move the content right and decrease the camera offset. This
  calls the public `CScrollingAlgorithm::moveTape` used by the stock gesture.
  It does not select windows, warp the pointer, choose a snap target, or implement
  animations. Hyprland recalculates the tape and animates the windows itself.
- `hl.plugin.tape.pan(delta, true)` explicitly places the tape at the requested
  offset for half-screen placement. It temporarily uses the public controller's
  scroll inhibitor during one native recalculation so that a short tape is not
  automatically recentered. The previous inhibitor state is immediately restored;
  an existing active inhibitor causes a clean refusal. The legacy two-argument call needs a navigable focused workspace. Subsequent native layout recalculations regain the usual centering
  policy. This is reserved for deliberate half placement, never ordinary browsing.
- `hl.plugin.tape.snapshot()` returns the native camera `offset`, primary viewport
  `width`, and usable-area `x`, `y`, `height`. Coordinates are monitor-local logical
  pixels. These are layout goals, so they remain useful while windows animate.
- `hl.plugin.tape.snapshot(workspaceId, monitorName)` reads a displayed scrolling
  workspace independently of keyboard focus. `hl.plugin.tape.pan(delta, exact,
  workspaceId, monitorName)` pans that same addressed workspace without activating
  it. These calls support a floating focused window and another focused monitor;
  stale monitor/workspace context, real fullscreen, active native drag, and an
  existing inhibitor are rejected before a pan. This path powers close repair.
- `hl.plugin.tape.info()` returns `protocolVersion=2`, capability flags
  `addressedCamera`, `ownedRegions`, and `reorder`, the current live
  `protectedRegionCount`, the callback's actual loaded library `path`, and
  compile-time `git_hash`. The path comes from the dynamic linker, so rebuild
  validation checks which binary supplies the functions, not just a plugin name.
- `hl.plugin.tape.protect_bar_region(monitorName, x, y, width, height, owner)` registers
  the layout strip's current bounds in global logical coordinates. The shell
  renews these leases independently of state snapshots; registration expires after
  3.5 seconds. Passing width and height both zero clears only this owner's lease.
  Replacing a shell service uses a fresh owner, so late cleanup from its predecessor
  cannot remove current protection. Registrations must fit the named live monitor.
  A maximum of 256 live owner/output pairs bounds memory use.

  Only a native mouse press whose actual pointer surface belongs to the Omarchy
  bar (or its keyboard-panel forwarding layer), and whose pointer point is inside
  the registered strip, activates protection. Other widgets and desktop clicks
  are unaffected. The bridge temporarily leases the old focused tiled window's
  workspace scroll inhibitor, including when focus belongs to another monitor.
  It retains the lease through the entire native mouse-release signal and restores
  it at event-loop idle, before the shell's asynchronous navigation request.

  This corrects a Hyprland 0.56.2 scrolling-layout behavior: the native release
  listener tests overlap using the cursor image's full rectangle. A cursor in the
  bar can overlap a clipped focused app below it, causing a wrong-way focus fit
  before the strip's requested navigation begins. Acquiring on press and releasing
  after all release listeners prevents that fit regardless of listener order.
  No focus, pointer or camera move occurs when protection starts or ends.

  Existing independent inhibitors are never acquired or overwritten. Cleanup
  handles lost/cancelled releases, stale workspaces and plugin unload; a two-minute
  maximum hold prevents indefinite inhibition. Once all physical buttons are up,
  bridge actions also clear a completed lease before they run. Native window
  dragging is excluded, and floating/fullscreen focus needs no protection.
- `hl.plugin.tape.reorder(sourceAddress, targetAddress, side, workspaceId, monitorName)`
  moves the source's complete scrolling column immediately `"before"` or `"after"`
  the target's column. Addresses are `"0x..."` strings, the workspace ID is an
  integer, and the monitor name identifies the displayed workspace. Native
  column/strip identities move together, preserving widths, stacked members, and
  every other column's relative order. Stable source/neighbor identities are
  checked again when the call arrives. Dropping into the same position is a no-op.

  Reorder does not focus or activate any window, switch monitors/workspaces,
  change focus history, or warp the pointer. It addresses the workspace directly,
  including while a floating window or another monitor has keyboard focus. It
  keeps a previously visible focused column stationary where possible; otherwise
  it anchors the largest visible unchanged column. Moving an offscreen column
  across the visible group compensates the camera so that group stays put. If the
  moved column itself was both focused and visible, the camera moves only as much
  as needed to keep it visible. An already offscreen focused source does not cause
  navigation. Native boundaries can limit exact anchor preservation. Existing
  deliberate half-placement margins remain permitted. Hyprland's own animation
  runs from one final native recalculation, with no temporary focus changes.
  Targets wholly offscreen in their old/current and new geometry finish their
  native geometry animation immediately, preventing an offscreen move from
  sweeping across visible apps. Targets visible before/after, already animating
  through the viewport, or retaining the same goal keep their normal animation.

  Reorder refuses stale/unmapped/hidden/floating source or target windows, an
  inactive displayed workspace, a changed monitor, real fullscreen, a native
  desktop window drag, or an existing scroll inhibitor. It returns
  `{ok=true, changed=boolean, sourceIndex=oldIndex, targetIndex=newIndex,
  offsetBefore=number, offsetAfter=number, anchorPreserved=boolean,
  suppressedAnimations=number}` on success,
  or `{ok=false, error=string}` before mutation when validation fails. Indices are
  zero-based. There is no keyboard-focus fallback when this function is absent.

Successful calls return a table with `ok = true`. Invalid arguments or a
non-scrolling / fullscreen workspace or focused floating window return
`{ok = false, error = "..."}`. Empty tapes may return valid geometry but have no
windows to navigate. Pan and snapshot resolve the focused monitor's active special
workspace, if any, otherwise its active workspace. Info does not require a focused
window or a scrolling workspace. The Lua caller owns navigation policy and should
check `ok` and handle an absent plugin by using its fallback.

The bridge uses the supported `HyprlandAPI::addLuaFunction` registration API and
public layout methods. It also listens to native mouse-button and floating-state
events to correct one upstream drag case: dropping a tiled column into the empty
left gutter before the tape's first column otherwise appends it at the far end.
The correction verifies that exact native append and uses native `swapcol l`
operations to put it at the beginning, preserving its original column width.
It applies only to a left-button move within the original workspace and monitor
on a horizontal rightward tape. Actual target drops, stacking, transfers,
fullscreen, floating-window drags, and screen edges in the middle of a tape
retain native behavior. Event listeners are removed when the plugin unloads.

It adds no function hooks, private-member access, compositor patches, background
services, pointer/focus warps, or animation replacements.

## Build and upgrades

From this directory, run:

```sh
./build.sh
```

An optional first argument selects the output file. `CXX` can select a matching
compiler. The script also writes `build-info.lua` beside the output library:

```lua
return { version = "0.56.2", git_hash = "..." }
```

The configuration loader can compare `version` against `hl.version()` before
attempting to load an old library. The native initialization guard still checks
the full ABI and exact commit; matching release versions alone are insufficient.
The actual compile operation is:

```sh
g++ -std=c++26 -shared -fPIC -fno-gnu-unique -O2 -Wall -Wextra \
  $(pkg-config --cflags hyprland lua) tape.cpp -o tape.so
```

The script compiles to a temporary file and renames it atomically, avoiding
truncation of a library already mapped by a compositor. It does not load, unload,
or reload Hyprland. `-fno-gnu-unique` lets the dynamic loader unload the library
instead of retaining an obsolete image across later rebuilds. Compile with the headers and compiler family/major used by the
installed compositor. The initial build used Hyprland 0.56.2 headers, default Lua
5.5.1 headers, and GCC 16.2.1; the installed compositor was built by GCC 16.1.1.

Initialization checks both Hyprland's full plugin ABI descriptor (including
supporting library versions) and its exact Git commit hash. After a Hyprland or
relevant library update, rebuild against the new installed headers before loading
the plugin in a compositor running that version. If the compositor has not yet
been restarted after a package upgrade, its version may differ from the headers;
the guard intentionally refuses that load. Until a matching bridge is available,
the Lua configuration must retain its fallback navigation path.

The durable installation lives at `~/.local/share/hypr-tape/`:

```text
tape.cpp
Reorder.hpp                        # pure reorder and camera policy
BarPressGuard.hpp                  # scoped inhibitor lease and strip bounds
build.sh
active.lua                         # selected path/version/Git hash
builds/<unique-build>/tape.so        # immutable build path
builds/<unique-build>/build-info.lua
```

The user configuration calls `require("hypr.tape-native").load()`. That loader
reads `active.lua`, checks its release version against `hl.version()`, checks the
library exists, and declares it through supported `hl.plugin.load`. Missing or
mismatched builds produce a native Hyprland notification and leave the fallback
controls available. Hyprland itself reports native ABI/load failures.

After a package update, restart into the updated compositor and run the installed
`hypr-tape-rebuild` command. The wrapper builds a fresh unique path, checks the
headers match the running release and commit, atomically selects its manifest,
reloads the configuration, and verifies `info().path` and `configerrors`. On
failure it restores the previous manifest and reloads, explicitly reporting a
rollback failure if one occurs. Old build directories are retained for rollback.
No watcher or background rebuild service is needed. The build operation alone is
also available explicitly:

```sh
~/.local/share/hypr-tape/build.sh
```

That command only creates `tape.so` and `build-info.lua` at the installation root;
it does not change `active.lua` or switch the loaded plugin. Use the wrapper to
activate a rebuild. Hyprland's configuration plugin manager handles removal of
the previous declared path and loading of the new one. A build failure leaves the
active manifest and its previously built library untouched.

The wrapper accepts `--data-dir /absolute/private/install` for isolated testing;
the loader accepts the same directory as an optional `load(base)` argument. The
wrapper otherwise uses the current Hyprland instance from the normal environment.

Lua functions are removed on plugin unload. Normal configuration reloads are
managed by Hyprland's plugin Lua registration API; the Lua module should resolve
`hl.plugin.tape` at call time rather than capture function references permanently.

## Private test session

The task's private compositor can be controlled with:

```sh
python ../headless/ctl.py plugin load "$PWD/tape.so"
python ../headless/ctl.py plugin list
```

Its helper supplies a separate runtime directory and instance signature. Do not
replace this helper with bare `hyprctl` when testing against the live user session.
