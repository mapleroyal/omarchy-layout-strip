# Layout Strip

An Omarchy menu bar plugin showing app icons and column widths in Hyprland's
scrolling layout.

![Layout Strip in Tiles mode, showing half, two-thirds, and full-width columns](preview.png)

## Features

- See one app icon per tiled column, in workspace order, with the focused column
  highlighted. Floating windows are omitted; stacks use one representative.
- Show column widths as accent underlines or proportional tiles. Both follow
  the shell's colors, icon sizing, and rounded/square corners.
- Click a column to focus it. An optional native bridge also aligns its left
  edge with the workspace's viewport, within the layout's legal range.
- Scroll overflow with a mouse wheel, horizontal trackpad gesture, or arrows.
  Choose arrows that scroll on hover or while held.
- Follow the displayed workspace independently on each monitor.

## Install

```bash
omarchy plugin add https://github.com/mapleroyal/omarchy-layout-strip.git --enable
omarchy bar move io.github.mapleroyal.layout-strip --section left --index 9999
```

Keep Layout Strip **last in the left bar section**. It centers itself in the
gap before the center section and uses up to 85% of that space. The second
command places it last (Omarchy clamps the index to the section's length).

Requires Omarchy's built-in horizontal bar, Hyprland's scrolling layout and Lua
IPC, Quickshell, and Python 3. Tested with Omarchy 4.0.2-1, Hyprland 0.56.2-1,
Quickshell 0.3.1-1, and Python 3.14.7-1. Vertical bars are unsupported.

The display and focus controls need no extra configuration. For exact left-edge
alignment, see the [optional native bridge](native/README.md); it must match the
running Hyprland build. Existing `omarchy_tape_bar` integrations are reused.

## Use

Right-click an icon, empty strip space, or either overflow arrow to choose
**Underlines / Tiles** and **Scroll on hover / Scroll on click**. In click mode,
tap an arrow to advance one step or hold it to keep scrolling. Your choices
survive shell reloads.

Window events refresh the strip, with a one-second fallback for resizing and
reordering. Empty or non-scrolling workspaces show no icons. The plugin reads
window metadata locally, focuses windows on click, and saves menu choices through
Omarchy. It makes no network requests and installs no system service.

See [development and compatibility](DEVELOPMENT.md) for the backend, diagnostics,
and validation commands.

## Remove

```bash
omarchy plugin remove io.github.mapleroyal.layout-strip
```

If you enabled the optional native bridge, remove its Hyprland config line first
as described in [its guide](native/README.md).

## License

Plugin code is [MIT licensed](LICENSE). The preview is an isolated rendering
with sample windows; shown application icons belong to their respective owners.
