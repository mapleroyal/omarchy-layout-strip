# QML interaction tests

Run `python3 tests/qml/run.py` from the repository. The runner creates a
temporary configuration and private runtime directory, uses Qt's offscreen
software renderer, and clears the desktop display/compositor environment
(including inherited Wayland sockets). It never opens a live preview or
moves the user's desktop viewport. Navigation is disabled, and settings writes
are recorded by an in-memory Omarchy host fixture.

The default run exercises the same suite twice: the older direct Loader host
and the current pooled WidgetHost hierarchy, with the bar's left-button
drag/click overlay as a sibling of the widget's slot branch. The fixture retains
the host's registered-target click forwarding and drag threshold. This catches
an input regression that a widget-only fixture misses: raising only the Loader
no longer clears that overlay after the host adds holder and pool containers.
Unplacing and reclaiming the widget also checks that the stacking override is
released and reacquired, and that a real left click still reaches its tile.
Use `--host legacy` or `--host pooled` to run one host in isolation.

The suite sends real QtTest mouse moves, button presses/releases, and wheel
events to the actual plugin and its visual components. It currently checks
assertions covering input, geometry, appearance, drag/drop, resize,
forwarded hitboxes, stable delegate identity, popup anchoring, metadata during
a press or glide, stale-data recovery, focus visibility, busy feedback, and
latest-only focus queueing. Middle-click coverage includes release timing,
the clicked address, popup forwarding, busy and
resize suppression, and middle input during/after a cancelled drag.
Right-click coverage includes release timing, the addressed width-cycle action,
clipped tiles, popup forwarding, busy/resize suppression, and drag cancellation.
Tile wheel coverage checks forward/reverse Super+O actions, addressed context,
fine wheel and trackpad accumulation, inverted mouse delivery, and suppression
during busy actions, resizing, or a held mouse button. Horizontal tile scrolling
and vertical arrow scrolling continue to browse strip overflow.
The captured Wayland mouse event with both 120 angle units and 15 pixel units
must perform one cycle; fine hybrid angles still accumulate, while pixel-only
gestures retain their threshold and overflow scrolling remains continuous.
Shrinking a tile keeps the stationary pointer's cycle on its original address;
moving the pointer selects a new target.
Drag/drop coverage also checks that both insertion boundaries around every
source hide the marker, that moving elsewhere restores it, and that dropping
back in the original position emits no reorder or focus action.

Stack coverage exercises the actual badge, member popup rows and close controls,
top-to-bottom order, fixed column identity across representative changes,
press-time addressing, menu updates after closing members, stale data, popup
coordination, and clipped forwarded badge targets. Drag tests change the stack
representative both before and after the drag threshold. Wheel tests follow the
same window when it floats out of its original stack.

Use `python3 tests/qml/run.py --screenshots /path/to/work/screenshots` for 1x and
2x renders of the 26-pixel strip in both appearance modes and the member menu.
When both hosts run, their captures are kept in separate host subdirectories.

Only the Wayland-specific container is substituted: `KeyboardPanel.qml`
preserves the host's open/close coordinator contract in an offscreen QtQuick
Window, allowing real popup row input without creating a layer-shell surface.
The bar is also hosted in an offscreen QtQuick Window.
This does not test compositor keyboard-focus priming or popup layer stacking;
those need a separate private compositor integration test. The plugin's
production components are not changed or copied into alternative test versions.

`shell.qml` also remains usable in a private Wayland compositor with the real
Omarchy `Commons`/`Ui` imports and the plugin linked as `LayoutStrip`. Never run
that form against the user's live display to generate a preview.
