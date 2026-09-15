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

-- The Close action targets the middle-clicked window while another is active.
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

-- Background width cycling must never focus, warp, or run navigation cleanup.
local resize_calls, invalidated = {}, {}
local resize_reply = { ok = true, changed = true }
local resize_enabled = true
function hl.plugin.tape.info() return {ok=true,protocolVersion=2,addressedResize=resize_enabled} end
function hl.plugin.tape.resize_column(address, width, workspace_id, monitor_name)
  resize_calls[#resize_calls + 1] = {address, width, workspace_id, monitor_name}
  assert(active == windows[2], "inactive width edit must preserve keyboard focus")
  if resize_reply.ok then windows[3].layout.column.width = width end
  return resize_reply
end
local cycle = Bar.new(hl, {
  jump = function() error("Background width edit must not jump") end,
  resize = function() error("Background width edit must not resize the active window") end,
  invalidate_workspace = function(workspace_id) invalidated[#invalidated+1] = workspace_id end,
}, function() error("Background width edit must not run navigation/pointer cleanup") end)
for _, expected in ipairs({0.667, 1, 0.5, 0.667}) do
  assert(success(cycle.cycle_width("0x3", 1, "eDP-1")))
  assert(windows[3].layout.column.width == expected and active == windows[2])
end
assert(#resize_calls == 4 and #invalidated == 4)
assert(table.concat(resize_calls[1], "|") == "0x3|0.667|1|eDP-1")
assert(invalidated[1] == 1)
for _, example in ipairs({{0.55, 0.667}, {0.7, 1}, {0.92, 0.5}}) do
  windows[3].layout.column.width = example[1]
  assert(success(cycle.cycle_width("0x3", 1, "eDP-1")))
  assert(windows[3].layout.column.width == example[2])
end
local resize_count, invalidation_count = #resize_calls, #invalidated
failure(cycle.cycle_width("0x3", 9, "eDP-1"), "no longer displayed")
failure(cycle.cycle_width("0x3", 1, "missing"), "no longer available")
failure(cycle.cycle_width("0xdead", 1, "eDP-1"), "no longer in this workspace")
failure(cycle.cycle_width("0x3; bad()", 1, "eDP-1"), "Invalid window address")
windows[3].floating = true
failure(cycle.cycle_width("0x3", 1, "eDP-1"), "no longer a visible scrolling column")
windows[3].floating = false
windows[3].fullscreen = 1
failure(cycle.cycle_width("0x3", 1, "eDP-1"), "Leave fullscreen")
windows[3].fullscreen = 0
resize_enabled = false
failure(cycle.cycle_width("0x3", 1, "eDP-1"), "needs addressed column resizing")
resize_enabled = true
assert(#resize_calls == resize_count and #invalidated == invalidation_count)
resize_reply = { ok = false, error = "Resize refused" }
failure(cycle.cycle_width("0x3", 1, "eDP-1"), "Resize refused")
assert(#invalidated == invalidation_count and active == windows[2])
resize_reply = { ok = true, changed = false }
assert(success(cycle.cycle_width("0x3", 1, "eDP-1")))
assert(#invalidated == invalidation_count and active == windows[2])
-- Super+O scrolling shares the keyboard helper's addressed cycle state. A
-- floated column must remain a tile even after native column indices shift.
local window_cycles, cycle_calls, cycle_invalidated = {}, {}, {}
local cycle_reply = {ok=true}
function omarchy_window_width_cycle_state(window) return window_cycles[window.address] end
function omarchy_cycle_window_width(window, direction)
  cycle_calls[#cycle_calls+1] = {window, direction}
  assert(active == windows[2], "backend must not refocus before the shared cycle helper")
  return cycle_reply
end
function hl.dsp.focus(args) return {focus=args.window.address} end
function hl.plugin.tape.info() return {ok=true,protocolVersion=2,reorder=true} end
local window_cycle = Bar.new(hl, {
  available = function() return true end,
  invalidate_workspace = function(id) cycle_invalidated[#cycle_invalidated+1] = id end,
  jump = function() error("Cycle-owned floating focus must not use tiled navigation") end,
}, function(result) return result end)
local function columns(reply)
  local result = {}
  for item in reply:match('"columns":(%b[])'):gmatch('%b{}') do
    result[#result+1] = {address=item:match('"address":"([^"]+)"'),
      index=tonumber(item:match('"index":(%d+)')), size=item:match('"size":"([^"]+)"')}
  end
  return result
end
for _, direction in ipairs({1, -1}) do
  assert(success(window_cycle.cycle_window("0x1", 1, "eDP-1", direction)))
  assert(cycle_calls[#cycle_calls][1] == windows[1] and cycle_calls[#cycle_calls][2] == direction)
end
assert(success(window_cycle.cycle_window("0x1", 1, "eDP-1")))
assert(cycle_calls[#cycle_calls][2] == 1 and #cycle_invalidated == 3)
window_cycles["0x1"] = {stage=1,floating=false,layout={name="scrolling",column={index=0,width=0.5}}}
windows[1].floating, windows[1].layout = true, nil
windows[2].layout.column.index, windows[3].layout.column.index = 0, 1
local floated_snapshot = window_cycle.snapshot("eDP-1")
local floated_columns = columns(floated_snapshot)
assert(#floated_columns == 3 and floated_columns[1].address == "0x1" and floated_columns[1].size == "medium")
assert(floated_columns[2].address == "0x2" and floated_columns[3].address == "0x3")
assert(floated_snapshot:find('"reorderAvailable":false', 1, true))
assert(success(window_cycle.cycle_window("0x1", 1, "eDP-1", -1)))
assert(cycle_calls[#cycle_calls][1] == windows[1] and cycle_calls[#cycle_calls][2] == -1)
window_cycles["0x1"].stage = 2
assert(columns(window_cycle.snapshot("eDP-1"))[1].size == "small")
assert(success(window_cycle.focus("0x1", 1, "eDP-1")))
assert(dispatched[#dispatched].focus == "0x1")
assert(success(window_cycle.close("0x1", 1, "eDP-1")))
assert(dispatched[#dispatched].close == "address:0x1")

-- A second cycle can save the same native index as an existing placeholder.
-- Its prior logical position keeps both floated tiles and the remaining tile.
assert(success(window_cycle.cycle_window("0x2", 1, "eDP-1", 1)))
window_cycles["0x2"] = {stage=1,floating=false,layout={name="scrolling",column={index=0,width=0.5}}}
windows[2].floating, windows[2].layout = true, nil
windows[3].layout.column.index = 0
local multiple = columns(window_cycle.snapshot("eDP-1"))
assert(#multiple == 3)
for i=1,3 do assert(multiple[i].address == "0x" .. i and multiple[i].index == i-1) end

local cycle_count, cycle_invalidation_count, dispatch_count = #cycle_calls, #cycle_invalidated, #dispatched
for _, direction in ipairs({0, 2, -2, "1", true}) do
  failure(window_cycle.cycle_window("0x1", 1, "eDP-1", direction), "Cycle direction")
end
failure(window_cycle.cycle_window("0x1", 9, "eDP-1", 1), "no longer displayed")
failure(window_cycle.cycle_window("0x1", 1, "missing", 1), "no longer available")
failure(window_cycle.cycle_window("0xdead", 1, "eDP-1", 1), "no longer in this workspace")
failure(window_cycle.cycle_window("0x1;bad()", 1, "eDP-1", 1), "Invalid window address")
windows[1].hidden = true
failure(window_cycle.cycle_window("0x1", 1, "eDP-1", 1), "no longer a visible scrolling column")
windows[1].hidden = false
local first_cycle = window_cycles["0x1"]
window_cycles["0x1"] = nil
for _, action in ipairs({"cycle_window", "focus", "close"}) do
  failure(window_cycle[action]("0x1", 1, "eDP-1"), "no longer a visible scrolling column")
end
window_cycles["0x1"] = first_cycle
first_cycle.floating = true
failure(window_cycle.cycle_window("0x1", 1, "eDP-1"), "no longer a visible scrolling column")
first_cycle.floating = false
assert(#cycle_calls == cycle_count and #cycle_invalidated == cycle_invalidation_count and #dispatched == dispatch_count)
cycle_reply = {ok=false,error="Window cycle failed"}
failure(window_cycle.cycle_window("0x1", 1, "eDP-1"), "Window cycle failed")
assert(#cycle_invalidated == cycle_invalidation_count)
omarchy_cycle_window_width = nil
failure(window_cycle.cycle_window("0x1", 1, "eDP-1"), "Super+O window cycle is unavailable")

-- A lone floating cycle keeps its actual stage size, despite single-column
-- fullscreen configuration. Unrelated floating windows never enter the strip.
windows[2].hidden, windows[3].hidden = true, true
function hl.get_config() return true end
assert(columns(window_cycle.snapshot("eDP-1"))[1].size == "small")
omarchy_window_width_cycle_state = nil
assert(#columns(window_cycle.snapshot("eDP-1")) == 0)
print("Bar action contracts passed (fake compositor; no real windows changed)")
