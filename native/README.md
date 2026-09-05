# Optional left-edge alignment

The strip works without this bridge. Enable it only if clicking a column should
also align its left edge. If `hl.plugin.tape` is already loaded by your own
configuration, use that installation and skip these steps.

This source is the author's native tape bridge. Besides camera access, it
corrects Hyprland's leading-gutter drag case: dropping a tiled column before the
first column places it first instead of appending it last. It uses public layout
methods and Lua plugin registration, with no function hooks or compositor patch.

## Build and enable

Requires a C++26 compiler, `pkg-config`, Hyprland development headers and Lua
headers matching the running compositor. Tested with Hyprland 0.56.2, Lua 5.5.1,
and GCC 16.2.1. On Omarchy these headers ship with the `hyprland` and `lua`
packages; install `base-devel` if the build tools are missing.

```bash
mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-layout-strip/native"
bash "$HOME/.config/omarchy/plugins/io.github.mapleroyal.layout-strip/native/build.sh" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-layout-strip/native/tape.so"
```

Add this line to your own `~/.config/hypr/hyprland.lua`:

```lua
hl.plugin.load((os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/omarchy-layout-strip/native/tape.so")
```

Then run `hyprctl reload` and `hyprctl configerrors`. This opt-in step loads
native code into the compositor; check that the errors list is empty.

## Updates and removal

The native initializer checks Hyprland's complete plugin ABI and exact Git
commit. After a Hyprland or supporting-library update, rebuild with the command
above, then log out and back in. The build command never reloads Hyprland, and a
config reload alone does not guarantee replacement of an already loaded library
at the same path. Until a matching library is loaded, the strip retains ordinary
window focus without exact camera alignment.

To remove, delete the `hl.plugin.load` line, run `hyprctl reload`, verify
`hyprctl configerrors`, then remove the dedicated directory:

```bash
rm -r "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-layout-strip/native"
```

## API

`hl.plugin.tape.snapshot()` reads the active scrolling camera, `pan(delta)` moves
it by logical pixels, and `info()` identifies the loaded library and build hash.
Calls return `{ok=true, ...}` or `{ok=false, error="..."}`. Lua owns focus and
alignment policy. The strip resolves the bridge at call time and never loads it
automatically.
