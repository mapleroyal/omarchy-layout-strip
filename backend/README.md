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

## Protocol v2

Check `omarchy_tape_bar.protocol_version == 2` before requests. Every reply contains `protocolVersion: 2` and a boolean `ok`.

- `snapshot(monitor)` is read-only and returns one monitor's column state.
- `snapshot_all({monitor1, monitor2})` returns `{ok, protocolVersion, snapshots:[...]}`.
- `protect_region(monitor, x, y, width, height, owner)` refreshes one input lease.
- `protect_regions({{monitor=...,x=...,y=...,width=...,height=...},...}, owner)` refreshes or clears a batch independently of state polling.
- `focus(address, workspaceId, monitor)`, `close(...)`, and `reorder(address, targetAddress, side, workspaceId, monitor)` keep addressed action validation.

Region coordinates are global logical pixels. Both positive dimensions register a region; both zero clear only the supplied owner's registration. A replacement shell must use a new owner token. Leases expire after 3500ms, even when a shell dies without clearing. One owner can register one region per monitor. Each snapshot exposes `nativeProtocolVersion`, `capabilities.addressedCamera`, `capabilities.ownedRegions`, `reorderAvailable`, and `protectRegionAvailable`. Missing native-v2 capabilities disable unsupported operations rather than guessing at another protocol.

The legacy Python CLI remains for diagnostics and scripted one-shot actions, with normalized hexadecimal addresses. The shell uses direct `hyprctl repl` requests and has no Python polling dependency.
