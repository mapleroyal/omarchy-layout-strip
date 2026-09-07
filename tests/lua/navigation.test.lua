local base = arg[1] or "work/scrolling-integration/"
local Tape = dofile(base .. "tape.lua")
local Bar = dofile(base .. "tape-bar.lua")
local active, current, offset, monitors, windows, commands
local hl = { plugin = { tape = {} }, dsp = {} }
function hl.get_active_workspace() return current end
function hl.get_active_special_workspace() return nil end
function hl.get_active_window() return active end
function hl.get_workspace_windows(workspace) return windows[workspace.id] or {} end
function hl.get_monitors() return monitors end
function hl.get_config() return true end
function hl.dsp.layout(command) return { command = command } end
function hl.dsp.focus(args) return { focus = args.window } end
function hl.dispatch(action)
  commands[#commands + 1] = action
  if action.focus then active = action.focus; current = active.workspace end
  return { ok = true }
end
function hl.plugin.tape.snapshot()
  if active and (active.floating or active.fullscreen ~= 0) then return { ok = false } end
  return { ok = true, width = 1200, offset = offset }
end
function hl.plugin.tape.pan(delta) offset = offset - delta; return { ok = true } end
function hl.plugin.tape.info() return {ok=true,protocolVersion=2,addressedCamera=true,ownedRegions=true,reorder=true} end
local function reset(widths)
  local monitor = { id = 0, name = "eDP-1" }
  current = { id = 1, name = "1", tiled_layout = "scrolling", monitor = monitor }
  monitor.active_workspace = current
  monitors, windows, offset, commands = { monitor }, { [1] = {} }, 0, {}
  for index, width in ipairs(widths) do
    local window = { address = "0x" .. index, class = "app" .. index,
      title = 'quoted "title"\\\n雪\0', mapped = true, hidden = false, floating = false,
      fullscreen = 0, workspace = current }
    window.layout = { name = "scrolling", column = { index = index - 1, width = width, windows = { window } } }
    windows[1][index] = window
  end
  active = windows[1][1]
  return Tape.new(hl)
end
local tape = reset({0.5, 0.667, 0.5})
local r = tape.jump("0x2", 1, "eDP-1")
assert(r.ok and r.changed and r.aligned and math.abs(offset - 600) < 0.001)
assert(active.address == "0x2")
assert(commands[1].command == "inhibit_scroll 1" and commands[3].command == "inhibit_scroll 0")
r = tape.jump("0x3", 1, "eDP-1")
assert(r.ok and math.abs(offset - 800.4) < 0.001, "last column must clamp to right edge")
for index, width in ipairs({0.5,0.667,0.5}) do assert(windows[1][index].layout.column.width == width) end
local before = #commands
assert(not tape.jump("0x2", 2, "eDP-1").ok)
assert(not tape.jump("0xdead", 1, "eDP-1").ok)
assert(not tape.jump("0x2", 1, "missing").ok)
assert(#commands == before, "stale selection must not change focus")
tape = reset({0.5,0.667,1})
active = { address = "0xf", floating = true, fullscreen = 0, workspace = current }
local bar = Bar.new(hl, tape, function(result) return result end)
local snapshot = bar.snapshot("eDP-1")
assert(snapshot:find('"size":"medium"',1,true), "floating focus must keep columns available")
r = tape.jump("0x1",1,"eDP-1")
assert(r.ok and r.changed and r.aligned and active.address == "0x1" and offset == 0)
-- Focus another monitor, then align using its camera in the same call.
local target = current
local second = { id = 1, name = "DP-2" }
current = { id = 2, name = "2", tiled_layout = "scrolling", monitor = second }
second.active_workspace = current
monitors[2] = second
active = nil
r = tape.jump("0x2", 1, "eDP-1")
assert(r.ok and r.changed and current == target and offset == 600)
-- Full-width ordinary columns are navigable. Actual fullscreen uses focus fallback.
tape = reset({0.5,1,0.5})
r = tape.jump("0x2",1,"eDP-1")
assert(r.ok and r.aligned and offset == 600)
active.fullscreen = 1
r = tape.jump("0x2",1,"eDP-1")
assert(r.ok and not r.aligned)
-- A single native column occupies full width regardless of stored preference.
tape = reset({0.5})
bar = Bar.new(hl,tape,function(result) return result end)
print(bar.snapshot("eDP-1"))
-- Metadata ordering is independent of window discovery order.
tape = reset({0.5,0.667,1})
windows[1] = {windows[1][3],windows[1][1],windows[1][2]}
bar = Bar.new(hl,tape,function(result) return result end)
print(bar.snapshot("eDP-1"))
print(bar.snapshot("missing"))
io.stderr:write("Tape jump and metadata checks passed\n")
