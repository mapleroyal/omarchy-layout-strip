# Development

`BarWidget.qml` measures the built-in bar's left-to-center gap and renders the
strip. `Model.js` handles wheel direction, focus reveal, and offset bounds.
Settings (`arrowMode`, `indicationMode`) live inline in the widget's `shell.json`
entry and are saved through the host's `updateEntryInline` API.

`backend/transport.py` sends a single argument-safe `hyprctl repl` request.
It loads the bundled Lua backend without modifying Hyprland configuration or
installing a helper on PATH. Existing `omarchy_tape_bar` integrations are reused
so their navigation completion hooks and keyboard/gesture coordination remain
intact. Otherwise each request creates a temporary backend from `tape-bar.lua`
and `tape.lua`; this does not register timers, hooks, keybindings, or globals.

Columns come from compositor metadata, never animated client coordinates.
Focus requests revalidate the displayed workspace, monitor, and window address.
The optional native bridge supplies exact camera placement; native focus remains
available when it is absent. No native binary is distributed.

## Compatibility

The QML uses Omarchy's `Commons` and `Ui` modules and the built-in bar's module
slots, click-target registration, and popout APIs. The backend requires
Hyprland's Lua API, including `window.layout.column`. These are version-sensitive
interfaces; the versions in the README are the tested baseline, not a promise
that older or future versions work.

Only horizontal bars, with the strip last on the left, are supported. Unusually
narrow gaps can hide the strip. Arbitrary column widths are grouped into the
nearest half / two-thirds / full indicator. Manual strip scrolling is preserved
until a focus or workspace change requires revealing the focused column.

## Validate

From the repository root:

```bash
omarchy plugin validate .
python3 -m unittest discover -s tests -p 'test_*.py'
lua tests/backend.lua
node tests/model.cjs
python3 tests/run_qml.py
```

The QML harness uses packaged Omarchy components, fake windows, and an in-memory
settings host. It briefly maps an isolated panel and sends QtTest pointer events;
real navigation is disabled. It checks input routing, scroll modes, overflow,
focus reveal, width indicators, theme corners, and persistence. Physical trackpad
inertia and a complete live multi-monitor interaction matrix remain manual
checks. `STRIP_TEST_POPUP=1 python3 tests/run_qml.py` also briefly opens the real
menu surface and saves fixture previews in the temporary test directory.

Read-only diagnostics (substitute an actual monitor name):

```bash
omarchy shell io.github.mapleroyal.layout-strip debug
python3 backend/transport.py snapshot --monitor eDP-1
```

Diagnostics include window titles and addresses; review them before sharing.
