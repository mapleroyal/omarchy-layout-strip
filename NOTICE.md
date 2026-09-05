# Dependencies and preview

The plugin uses [Omarchy](https://github.com/basecamp/omarchy) (MIT),
[Hyprland](https://github.com/hyprwm/Hyprland) (BSD 3-Clause),
[Quickshell](https://git.outfoxxed.me/quickshell/quickshell) (LGPL-3.0-only),
[Qt](https://www.qt.io/licensing/) (its applicable open-source or commercial
licenses), Python, and Lua. These dependencies are installed separately; their
source and binaries are not vendored here. The optional authored native bridge
includes Hyprland and Lua headers at build time and uses Hyprland's plugin API.
Their licenses continue to apply to those dependencies.

The preview renders sample windows using the installed OpenAI, Google Chrome,
and Obsidian application icons. Those names and icons remain the property of
their respective owners and are not relicensed by this project's MIT license.
