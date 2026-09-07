# Layout Strip 1.2

The maintained source for the installed `user1.layout-strip` Omarchy bar plugin
and its shared Hyprland scrolling backend. The native backend also supports the
existing keyboard and gesture navigation; removing the bar widget does not
remove that shared dependency.

See the [1.2.0 implementation and validation report](docs/implementation.md)
for completed fixes, measurements and installation results.

An icon represents one tiled column in the displayed workspace. Hover shows
the window title. There is no window-thumbnail or video-preview feature.
Internal references to the **camera** mean the desktop's horizontal scroll
position—which columns are visible—not a thumbnail or recording device.

## Interaction

- Click an icon to focus its window and align the column's left edge where the
  layout permits. Close an app from its right-click menu without first focusing it.
- Drag an icon to reorder whole columns; release outside or right-click during
  the drag to cancel. Hovering near the strip ends scrolls only the strip.
- Scroll overflow with wheel, trackpad or arrows. The arrow menu switches between
  hover scrolling and click/hold scrolling.
- Right-click blank space or an arrow for settings, width reset and placement.
  Drag either narrow edge to resize around the strip's fixed center.
- Underlines and Tiles show half/two-thirds/full column widths. Colors, corners
  and icons follow Omarchy. Horizontal bars are supported in all three sections;
  stacked columns use one representative window.

Tile interaction uses the pointer. The existing desktop keyboard and gesture
navigation continues through the shared backend; vertical bars, a separate
keyboard traversal mode for tiles, and individual stacked members are outside
this widget's current feature set.

## Reliability and performance

Stable models retain icon objects during title/focus updates, so updates do not
swallow clicks or move open menus. Harmless updates preserve scrolling animations.
Resizing keeps an already-visible focused icon visible while respecting deliberate
manual scrolling away from focus.

One Omarchy service handles all monitors through direct typed `hyprctl` RPCs.
State updates are event-coalesced with a one-second fallback only while visible.
Input-region leases refresh separately at 1.5 seconds and on geometry changes;
they clear on teardown and expire after 3.5 seconds if the shell disappears.
Geometry reacts to host changes without a polling timer. Python is used only by
diagnostic/installation commands, not background bar polling.

The service keeps only the latest queued focus request. Close and reorder are
never automatically retried or queued. A visible status mark reports unavailable
or stale backend data; hover it for the reason and click to retry a state read.

## Install or update

Required: Omarchy's Quickshell shell, Lua-enabled Hyprland scrolling layout,
Python 3 for installation/tools, and the matching Hyprland/Lua development headers,
GCC-compatible C++26 compiler and pkg-config for the native bridge.

Tested against Omarchy 4.0.2-1, Quickshell 0.3.1, Qt 6.11.2 and Hyprland 0.56.2.
Native binaries are tied to the exact compositor commit and full ABI. Update and
restart Hyprland before rebuilding against newly installed headers.

From this repository:

```sh
python3 tests/run.py
python3 install.py                       # read-only plan
python3 install.py --apply               # backup, install, native rebuild, widget swap
omarchy restart shell                    # load added components into a fresh QML engine
hypr-tape-doctor                         # read-only health check
```

The installer preserves `shell.json`, existing width/appearance/arrow choices,
the selected tape mode and unrelated user keybindings. It migrates only recognized
old integration blocks, or adds a narrow bootstrap on a clean installation.
Unexpected existing integration is refused instead of overwriting personal code.
The printed backup contains prior files and their paths.

Restart the shell after installing a release with new QML components. On the
tested Omarchy/Qt versions, a plugin rescan retained the old directory/component
cache and reported a misleading `File name case mismatch` for the new service.
The supported shell restart loads the complete release; Hyprland stays running.
The doctor verifies the active service as well as the Lua/native backend.

For a new installation, enable the widget through Omarchy after installation:

```sh
omarchy plugin enable user1.layout-strip
omarchy bar move user1.layout-strip --section left --index 9999
```

For staging into isolated directories, `--config-home`, `--data-home`, `--bin-dir`
and `--skip-native-build` are available. The last option intentionally leaves native
activation to a later rebuild; it is not needed for a normal install.

## Diagnostics and upgrades

```sh
omarchy shell user1.layout-strip debug
omarchy shell user1.layout-strip monitor eDP-1
hypr-tape-bar snapshot --monitor eDP-1
hypr-tape-rebuild
```

Debug output includes every monitor instance, workspace identity, transport/native
versions, capabilities, last successful refresh, errors and request counters.
The RPC protocol is version 2; incompatible frontend/backend installations are
reported before actions are sent. Missing native features retain ordinary focus
where possible and disable unsupported operations.

`hypr-tape-rebuild` builds an immutable versioned library, checks exact headers,
activates it, verifies the loaded path, and restores the previous manifest if
activation fails. Keep previous builds for rollback. Do not unload the bridge
just to disable this widget; keyboard/gesture navigation shares it.

## Source ownership and testing

| Directory | Responsibility |
|---|---|
| `plugin/` | QML service/controller, components, host adapter, pure models, icon resolver |
| `backend/` | Typed bar RPCs, scrolling policy, per-workspace repair, narrow bootstrap |
| `native/` | Addressed compositor operations, protected-input leases, build source |
| `bin/` | Optional CLI transport, health check, rebuild and mode tools |
| `tests/` | Model, host, protocol, scheduler, Lua, C++, installer and QML input tests |

The default test entry point uses mocked compositor calls and offscreen QtQuick
input. The real production popup component graph is separately load-checked.
`tests/native/headless.py` exercises the native plugin in an explicitly owned,
two-output compositor; it never falls back to the login desktop. Its graphics
parent requirements are documented alongside validation results. Physical trackpad
inertia and compositor popup stacking remain distinct from offscreen input tests.

To measure the installed direct read path without sending window actions, run
`python3 tests/benchmark.py --monitor eDP-1 --output /tmp/layout-strip-benchmark.json`
with your monitor name. The benchmark reports child-process CPU, not whole-shell
CPU or battery consumption.

See [host integration](docs/host-integration.md), [Lua adapter](backend/README.md),
[native API and upgrade safety](native/README.md), and [QML test scope](tests/qml/README.md).
