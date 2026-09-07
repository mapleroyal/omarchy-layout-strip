# Window preview feasibility — research only

Reviewed 7 September 2026 against installed Quickshell 0.3.1 and Hyprland
0.56.2. No preview feature or capture experiment was implemented.

The best existing dependency is already present: Quickshell's built-in
[`ScreencopyView`](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView/)
supports single-window stills and live capture. It can be attached to the Wayland
toplevel associated with a strip window address. The component handles capture
and rendering; plugin code would own only the hover popup, lifecycle and fallback.
Capturing successive rendered frames naturally includes videos and animations;
there is no need to identify GIFs, players or other content types.

The substantial limitation is the compositor. Hyprland 0.56.2
[skips pending captures for windows entirely outside their monitor](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/screenshare/ScreenshareManager.cpp#L31-L34).
From that code, a fresh preview of a fully offscreen scrolling column can remain
pending. Both supported capture protocols share this path. A bounded cache of
previously successful thumbnails, or the icon/title, is the appropriate fallback.
Covering a window with another window is different: capture
[renders that window separately](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/managers/screenshare/ScreenshareFrame.cpp#L284-L298).

Static snapshots have the lowest ongoing capture cost. Live mode should exist
only while one preview is actually shown, after a short hover delay, and stop
immediately on dismissal. Quickshell has single-frame requests and a live switch,
but no built-in frame-rate cap. Its small display constraint does not shrink the
underlying capture buffer; Hyprland also currently
[reports full-frame damage](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/protocols/ImageCopyCapture.cpp#L375).
Consequently, neither a tiny thumbnail nor visually static content guarantees
negligible live cost. Measure GPU/CPU and frame pacing before choosing a live default.

Always-running capture for every tile is not recommended. A static default with
optional live-on-hover would be the conservative starting point. Animation
freshness remains application-dependent: Wayland permits
[withholding frame callbacks from invisible surfaces](https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_surface-request-frame).

Existing utilities are less direct for embedding. Installed `grim 1.5.0` supports
single-window `-T` snapshots, useful for a static proof of concept. Quickshell's
component avoids repeatedly starting a utility and encoding temporary screenshots.
An existing example, [quickshell-share-picker](https://github.com/SamSaffron/quickshell-share-picker),
uses one selected-window `ScreencopyView`; it is an implementation reference,
not a required dependency. No extra capture framework is needed for the proposed
hover feature, and another client library would not remove Hyprland's offscreen gate.
