# Scrolling layout strip

Installed component of Layout Strip 1.0.0. The maintained source, installer,
backend, and complete test suite are in the source repository.

Hover an icon for its window title. There are no thumbnail/video previews.
Click to focus, drag to reorder, and middle-click a window item to close it;
app save prompts are honored. Right-click a tile to cycle its column's width
through half, two-thirds, full, then half again without changing focus or moving
the pointer. The visible layout stays anchored where its new width permits.
Scroll down over a tile to advance the custom Super+O window cycle (original →
centered floating two-thirds → half → original); scroll up to reverse it. Its
tile stays available while floating. This uses the shared cycle functions in
the user's Hyprland bindings. Horizontal scrolling still browses the strip;
vertical scrolling over arrows or blank space also browses overflow.
Right-click blank space or an arrow for settings; resize from either narrow edge.

Stable icon objects preserve clicks and menu anchors across metadata updates.
The shared Omarchy service reads all monitors directly through typed Hyprland
RPCs. Hidden strips stop polling; input protection renews independently and clears
on teardown. A status mark reports stale/unavailable data or busy actions.

Appearance, width and placement remain in your existing shell.json entry.

Read-only diagnostics:

```sh
omarchy shell user1.layout-strip debug
omarchy shell user1.layout-strip monitor eDP-1
hypr-tape-doctor
```

The shared native tape bridge also supports keyboard/gesture navigation; disabling
the strip does not unload it. Rebuild with hypr-tape-rebuild after updating and
restarting Hyprland. The backend requires protocol version 2.
