# QML interaction tests

Run `python3 tests/qml/run.py` from the repository. The runner creates a
temporary configuration, uses Qt's offscreen software renderer, and clears
the desktop display/compositor environment. It never opens a live preview or
moves the user's desktop viewport. Navigation is disabled, and settings writes
are recorded by an in-memory Omarchy host fixture.

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
Shrinking a tile keeps the stationary pointer's cycle on its original address;
moving the pointer selects a new target.
Drag/drop coverage also checks that both insertion boundaries around every
source hide the marker, that moving elsewhere restores it, and that dropping
back in the original position emits no reorder or focus action.

Only the Wayland-specific container is substituted: `KeyboardPanel.qml`
preserves the host's open/close coordinator contract without creating a
layer-shell surface. The bar itself is hosted in an offscreen QtQuick Window.
This does not test compositor keyboard-focus priming or popup layer stacking;
those need a separate private compositor integration test. The plugin's
production components are not changed or copied into alternative test versions.

`shell.qml` also remains usable in a private Wayland compositor with the real
Omarchy `Commons`/`Ui` imports and the plugin linked as `LayoutStrip`. Never run
that form against the user's live display to generate a preview.
