-- Action-boundary tests use fake compositor objects; no desktop is changed.
local base = arg[1] or "work/scrolling-integration/"
local Bar = dofile(base .. "tape-bar.lua")
local monitor = { id = 0, name = "eDP-1" }
local workspace = { id = 1, name = "1", tiled_layout = "scrolling", monitor = monitor }
monitor.active_workspace = workspace
local windows, active, native_calls, dispatched, finished = {}, nil, {}, {}, {}
for i = 1, 3 do
  windows[i] = { address = "0x" .. i, mapped = true, hidden = false, floating = false,
    fullscreen = 0, workspace = workspace,
    layout = { name = "scrolling", column = { index = i - 1, width = 0.5 } } }
end
active = windows[2]
local native_reply = { ok = true, changed = true, anchorPreserved = true }
local hl = { plugin = { tape = {} }, dsp = { window = {} } }
function hl.get_monitors() return { monitor } end
function hl.get_active_workspace() return workspace end
function hl.get_active_special_workspace() return nil end
function hl.get_active_window() return active end
function hl.get_workspace_windows(target) assert(target == workspace); return windows end
function hl.get_config() return false end
function hl.dsp.window.close(args) return { close = args.window } end
function hl.dispatch(action)
  dispatched[#dispatched + 1] = action
  return { ok = true }
end
function hl.plugin.tape.reorder(...)
  native_calls[#native_calls + 1] = { ... }
  return native_reply
end
function hl.plugin.tape.info() return {ok=true,protocolVersion=2,addressedCamera=true,ownedRegions=true,reorder=true} end
local native_reorder = hl.plugin.tape.reorder
local bar = Bar.new(hl, { invalidate_workspace=function() end, available = function() return true end,
  jump = function() error("Reorder/close must not jump to a window") end }, function(result)
  finished[#finished + 1] = result
  return result
end)
local function success(reply) return reply:find('"ok":true', 1, true) ~= nil end
local function failure(reply, message)
  assert(not success(reply), reply)
  assert(reply:find(message, 1, true), reply)
end

-- Reorder uses stable addresses and preserves native result metadata. Neither
-- an active-window change nor a pointer-refocus/navigation call is permitted.
local reply = bar.reorder("0x3", "0x1", "before", 1, "eDP-1")
assert(success(reply) and reply:find('"anchorPreserved":true', 1, true))
assert(#native_calls == 1 and #dispatched == 0 and #finished == 0 and active == windows[2])
assert(table.concat(native_calls[1], "|") == "0x3|0x1|before|1|eDP-1")
native_reply = { ok = true, changed = false }
assert(bar.reorder("0x1", "0x1", "after", 1, "eDP-1"):find('"changed":false', 1, true))
native_reply = { ok = false, error = "Workspace has a fullscreen window" }
failure(bar.reorder("0x1", "0x3", "after", 1, "eDP-1"), native_reply.error)

-- A menu/drag can outlive its original workspace or one of its windows. Every
-- stale variant must fail before any compositor mutation is dispatched.
local calls_before = #native_calls
failure(bar.reorder("0x3", "0x1", "before", 9, "eDP-1"), "no longer displayed")
failure(bar.reorder("0x3", "0x1", "before", 1, "missing"), "no longer available")
failure(bar.reorder("0x3", "0xdead", "after", 1, "eDP-1"), "no longer in this workspace")
failure(bar.reorder("0x3", "0x1", "invalid", 1, "eDP-1"), "before or after")
failure(bar.reorder("0x3", "0x1", "after", 1.5, "eDP-1"), "workspace ID")
failure(bar.reorder("0x3", "0x1", "after", 1, nil), "monitor name")
failure(bar.reorder("0x3; hostile()", "0x1", "after", 1, "eDP-1"), "Invalid window address")
windows[3].floating = true
failure(bar.reorder("0x3", "0x1", "before", 1, "eDP-1"), "no longer a visible scrolling column")
windows[3].floating = false
monitor.active_special_workspace = { id = -99, tiled_layout = "scrolling" }
failure(bar.reorder("0x3", "0x1", "before", 1, "eDP-1"), "no longer displayed")
monitor.active_special_workspace = nil
assert(#native_calls == calls_before and #dispatched == 0 and #finished == 0)

-- The Close action targets the right-clicked window while another is active.
-- Its successful result means the close request was sent, not that an app has
-- already exited; dispatch lets that app decide how to handle save prompts.
assert(success(bar.close("0x3", 1, "eDP-1")))
assert(#dispatched == 1 and dispatched[1].close == "address:0x3")
assert(active == windows[2] and #finished == 1 and #native_calls == calls_before)
failure(bar.close("0xdead", 1, "eDP-1"), "no longer in this workspace")
failure(bar.close("0x3", 2, "eDP-1"), "no longer displayed")
windows[3].hidden = true
failure(bar.close("0x3", 1, "eDP-1"), "no longer a visible scrolling column")
windows[3].hidden = false
assert(#dispatched == 1 and #finished == 1)

-- Missing/failed bridges report errors, while snapshots advertise capability.
assert(bar.snapshot("eDP-1"):find('"reorderAvailable":true', 1, true))
hl.plugin.tape.reorder = nil
assert(bar.snapshot("eDP-1"):find('"reorderAvailable":false', 1, true))
failure(bar.reorder("0x3", "0x1", "before", 1, "eDP-1"), "does not support reordering")
hl.plugin.tape.reorder = function() error("native failure") end
failure(bar.reorder("0x3", "0x1", "before", 1, "eDP-1"), "native failure")
hl.plugin.tape.reorder = function() return nil end
failure(bar.reorder("0x3", "0x1", "before", 1, "eDP-1"), "invalid action result")
hl.plugin.tape.reorder = native_reorder
print("Bar action contracts passed (fake compositor; no real windows changed)")
