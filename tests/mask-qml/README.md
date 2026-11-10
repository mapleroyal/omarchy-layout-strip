# Input-mask compatibility tests

Run `python3 tests/mask-qml/run.py`. The production `StripInputMask` component
is loaded against real Quickshell `FloatingWindow` and `Region` objects with
Qt's offscreen software renderer, a private runtime directory, and no inherited
desktop display or compositor connection.

The suite checks ownership and restoration of the host's empty input region.
Only the strip item is added while recovery is enabled. The host's null mask
during dragging, ordinary bar region, nonempty custom regions, and compound
regions remain untouched. Disabling recovery for visible fullscreen or stale
state, changing surfaces, losing the strip, and destroying the component must
all restore the prior empty region.

These checks cover QML bindings and mask objects; actual Wayland pointer
delivery and compositor fullscreen coverage remain separate integration checks.
