# Hyprland adapter

`tape.lua` owns navigation and per-workspace geometry-repair generations. `tape-bar.lua` exposes the protocol-v2 bar RPCs. `tape-bootstrap.lua` owns event subscriptions, deferred repairs, and stationary-pointer refresh; it defines no keybindings.

A clean integration loads these modules once in the user's Hyprland Lua configuration:

```lua
require("hypr.tape-native").load()
local tape = require("hypr.tape").new(hl)
local integration = require("hypr.tape-bootstrap").new(hl, tape, require("hypr.tape-bar"))
omarchy_tape_bar = integration.bar

-- Existing custom navigation bindings can wrap their result this way:
-- integration.finish_navigation(tape.focus("r", false))
-- Touchpad gesture handlers can defer pointer retargeting until release:
-- integration.begin_pointer_refocus_deferral()
-- integration.flush_pointer_refocus()
```

Retain the integration object for the configuration lifetime. Creating a replacement through the same bootstrap module disposes its predecessor. `integration.dispose()` can also be called explicitly; it is idempotent and removes both subscriptions, disables both timers, and discards pending repairs. Hyprland owns and destroys the Lua configuration's timer objects on configuration teardown.

Migration from the previous custom bindings changes only three integration blocks: the local pointer-refresh/RPC construction block, the close/fullscreen event handlers, and the two gesture-deferral helper functions. Use the installer migration rather than replacing an entire personal bindings file.

Smooth gesture updates use the native `pan_direct` operation when available so
the tape follows the fingers immediately. Release and cancellation retain normal
animation. Regrabbing an unfinished landing starts from its visible position;
only subsequent finger travel counts toward the next landing. The original goal
remains the cancellation target. Discrete navigation keeps ordinary animated
panning, and an older bridge without `pan_direct` keeps its existing behavior.

Scrolling-managed fullscreen windows participate in the same smooth gestures.
The native snapshot advertises `layoutFullscreen=true` after validating that
the workspace contains no unsupported fullscreen handler. Lua retains the
monitor-sized column width and treats its covering range as one resting view,
including at the ends of the tape. Swiping away, returning, or cancelling never
toggles the window's internal or client fullscreen state. A fullscreen state
change during a gesture invalidates its saved geometry. Other fullscreen
handlers and older bridges retain their existing focus fallback.

This path does not require changing `binds.movefocus_cycles_fullscreen`: panning
reveals the destination before selecting it directly on release. Resizing and
half-placement still reject an active fullscreen window. The native bridge must
be rebuilt with the matching Lua sources before fullscreen tracking is enabled.

## Protocol v2

Check `omarchy_tape_bar.protocol_version == 2` before requests. Every reply contains `protocolVersion: 2` and a boolean `ok`.

- `snapshot(monitor)` is read-only and returns one monitor's column state. Each entry has a `columnId` stable across representative/focus changes, an addressed `address` for its active or last-used member, `memberCount`, and `members` ordered by compositor `index_in_column`. Members expose `address`, `class`, `title`, `focused`, `floating`, and `indexInColumn`. Existing representative fields remain available. IDs belong to the current Lua adapter lifetime, not durable storage.
- `snapshot_all({monitor1, monitor2})` returns `{ok, protocolVersion, snapshots:[...]}`.
- `protect_region(monitor, x, y, width, height, owner)` refreshes one input lease.
- `protect_regions({{monitor=...,x=...,y=...,width=...,height=...},...}, owner)` refreshes or clears a batch independently of state polling.
- `focus(address, workspaceId, monitor)`, `close(...)`, `cycle_window(address, workspaceId, monitor, direction)`, `cycle_width(...)`, and `reorder(address, targetAddress, side, workspaceId, monitor)` keep addressed action validation. Width cycling reads the live column width and calls native addressed resizing to cycle half, two-thirds, full, and half again. It preserves keyboard focus and pointer position, with camera compensation for the visible focused or largest unchanged column.

Mapped, visible floating windows receive their own entries with `floating: true`, whether or not Super+O restoration state is available. Former tiled windows retain a remembered strip position; a member detached from a stack gets a separate neighboring tile. Floating windows with no remembered tiled position follow tiled entries. `focus`, `close`, and `cycle_window` accept these windows. `cycle_width` and reorder endpoints remain tiled-only, and snapshots disable drag reordering while any floats are present.

Region coordinates are global logical pixels. Both positive dimensions register a region; both zero clear only the supplied owner's registration. A replacement shell must use a new owner token. Leases expire after 3500ms, even when a shell dies without clearing. One owner can register one region per monitor. Each snapshot exposes `nativeProtocolVersion`, `capabilities.addressedCamera`, `capabilities.ownedRegions`, `reorderAvailable`, and `protectRegionAvailable`. Missing native-v2 capabilities disable unsupported operations rather than guessing at another protocol.

The legacy Python CLI remains for diagnostics and scripted one-shot actions, with normalized hexadecimal addresses. The shell uses direct `hyprctl repl` requests and has no Python polling dependency.
