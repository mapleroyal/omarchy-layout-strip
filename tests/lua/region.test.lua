-- Native registration is mocked: this test cannot change the live compositor.
local base = arg[1] or "work/navigation-fix/"
local Bar = dofile(base .. "tape-bar.lua")
local monitor = { id = 0, name = "eDP-1" }
local workspace = { id = 1, name = "1", tiled_layout = "scrolling", monitor = monitor }
monitor.active_workspace = workspace
local calls = {}
local reply = { ok = true }
local native = {}
function native.protect_bar_region(...)
  calls[#calls + 1] = { ... }
  return reply
end
function native.info() return {ok=true,protocolVersion=2,addressedCamera=true,ownedRegions=true,reorder=true} end
local protect = native.protect_bar_region
local window = { address = "0x1", mapped = true, fullscreen = 0,
  layout = { name = "scrolling", column = { index = 0, width = 0.5 } } }
local hl = { plugin = { tape = native } }
function hl.get_monitors() return {monitor} end
function hl.get_active_workspace() return workspace end
function hl.get_active_special_workspace() return nil end
function hl.get_active_window() return window end
function hl.get_workspace_windows() return {window} end
function hl.get_config() return false end
local bar = Bar.new(hl, { available = function() return true end }, function(result) return result end)
local function contains(text, expected) assert(text:find(expected, 1, true), text) end

-- Plain snapshots remain read-only, even on a bridge supporting protection.
contains(bar.snapshot("eDP-1"), '"protectRegionAvailable":true')
bar.snapshot()
assert(#calls == 0)
local result = bar.snapshot("eDP-1", -122.5, -146, 415.5, 26)
contains(result, '"protectRegionRegistered":true')
assert(#calls == 1 and table.concat(calls[1], "|") == "eDP-1|-122.5|-146|415.5|26")
result = bar.snapshot("eDP-1", 0, 0, 0, 0)
contains(result, '"protectRegionRegistered":false')
contains(result, '"protectRegionCleared":true')
assert(not result:find('"protectRegionError":', 1, true))
assert(#calls == 2 and table.concat(calls[2], "|") == "eDP-1|0|0|0|0")

-- Validate direct Lua calls as well as CLI inputs. Invalid coordinates cannot
-- accidentally register an infinite or full-desktop protection region.
for _, values in ipairs({
  {"eDP-1", 0/0, 0, 100, 26}, {"eDP-1", 0, math.huge, 100, 26},
  {"eDP-1", 0, 0, -1, 26}, {"eDP-1", 0, 0, 100, 0},
  {"eDP-1", "0", 0, 100, 26}, {"", 0, 0, 100, 26},
  {"eDP-1", 0, 0, 100},
}) do
  result = bar.snapshot(table.unpack(values))
  contains(result, '"protectRegionRegistered":false')
  contains(result, '"protectRegionError":')
end
assert(#calls == 2)

-- Older native bridges and failed registrations must keep ordinary strip
-- snapshots usable while clearly exposing missing/failed protection.
native.protect_bar_region = nil
result = bar.snapshot("eDP-1", 0, 0, 100, 26)
contains(result, '"protectRegionAvailable":false')
contains(result, '"protectRegionRegistered":false')
contains(result, '"address":"0x1"')
native.protect_bar_region = protect
reply = { ok = false, error = "Region is outside the monitor" }
result = bar.snapshot("eDP-1", 0, 0, 100, 26)
contains(result, '"ok":true')
contains(result, '"protectRegionError":"Region is outside the monitor"')
contains(result, '"address":"0x1"')
native.protect_bar_region = function() error("Native registration failure") end
contains(bar.snapshot("eDP-1", 0, 0, 100, 26), "Native registration failure")
print("Optional strip-region registration contracts passed")
