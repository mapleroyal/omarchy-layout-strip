local Tape = dofile((arg[1] or "backend/") .. "tape.lua")
local monitors, windows, offsets, current, active, actions, reject
local hl = { dsp = {}, plugin = { tape = {} } }
function hl.get_active_workspace() return current end
function hl.get_active_special_workspace() return nil end
function hl.get_active_window() return active end
function hl.get_monitors() return monitors end
function hl.get_workspace_windows(ws) return windows[ws.id] end
function hl.get_config() return false end
function hl.dsp.focus(args) return { focus = args } end
function hl.dsp.layout(command) return { command = command } end
function hl.dispatch(action)
  actions[#actions + 1] = action
  if action.focus then
    if reject then return { ok = false, error = "focus rejected" } end
    local target = action.focus.window
    if action.focus.monitor then
      for _, monitor in ipairs(monitors) do
        if monitor.name == action.focus.monitor then target = windows[monitor.active_workspace.id][1] end
      end
    end
    if target then
      current, active = target.workspace, target
      -- Native monitor activation may align a remembered window. Browsing
      -- must restore the chosen stop from the view before activation.
      offsets[current.id] = 1000
    end
  end
  return { ok = true }
end
function hl.plugin.tape.info() return { ok = true, protocolVersion = 2, addressedCamera = true } end
function hl.plugin.tape.snapshot(id)
  if not id and active and active.workspace.id ~= current.id then return {ok=false} end
  return { ok = true, width = 1000, offset = offsets[id or current.id] }
end
function hl.plugin.tape.pan(delta, _, id)
  id = id or current.id
  offsets[id] = offsets[id] - delta
  return { ok = true }
end
local native = hl.plugin.tape
local function reset(offset)
  monitors, windows, offsets, actions, reject = {}, {}, {offset or 0, 500}, {}, false
  hl.plugin.tape = native
  for id = 1, 2 do
    local monitor = { name = "screen-" .. id, id = id }
    local ws = { id = id, tiled_layout = "scrolling", monitor = monitor }
    monitor.active_workspace = ws
    monitors[id], windows[id] = monitor, {}
    for i = 1, 4 do
      local w = { address = "0x" .. id .. i, workspace = ws, mapped = true,
        hidden = false, floating = false, fullscreen = 0 }
      w.layout = { name = "scrolling", column = { index = i - 1, width = 0.5, windows = {w} } }
      windows[id][i] = w
    end
  end
  current, active = monitors[2].active_workspace, windows[2][3]
  return Tape.new(hl)
end
for _, case in ipairs({{0,"r",500,3}, {1000,"l",500,2}}) do
  local tape = reset(case[1])
  local result = tape.browse_monitor(case[2], "screen-1")
  assert(result.ok and result.changed and current.id == 1)
  assert(offsets[1] == case[3] and active == windows[1][case[4]], "wrong browsing stop or focus")
  assert(offsets[2] == 500, "unrelated screen camera changed")
end
local tape = reset(0)
-- Hovering the target bar may switch the active monitor/workspace while the
-- previous monitor keeps keyboard focus. Its camera is addressed until focus
-- catches up; native directional fallback would choose the wrong column.
current = monitors[1].active_workspace
local result = tape.browse_monitor("r", "screen-1")
assert(result.ok and active == windows[1][3] and offsets[1] == 500 and offsets[2] == 500)
tape = reset(0)
assert(not tape.browse_monitor("up", "screen-1").ok)
assert(not tape.browse_monitor("r", "missing").ok)
assert(not tape.browse_monitor("r", nil).ok)
assert(#actions == 0, "invalid requests dispatched an action")
assert(not tape.browse_monitor("l", "screen-1").changed and #actions == 0, "clamped edge stole focus")
reject = true
assert(not tape.browse_monitor("r", "screen-1").ok and current.id == 2)
tape = reset()
hl.plugin.tape = nil
assert(tape.browse_monitor("r", "screen-1").ok and current.id == 1, "native fallback targeted wrong output")
tape = reset()
-- Same-output input delegates to the existing swipe policy exactly.
local called
tape.browse = function(direction, edge) called = {direction, edge}; return {ok=true,changed=false} end
assert(tape.browse_monitor("l", "screen-2").ok and called[1] == "l" and called[2] == false)
print("Monitor browsing: both directions, camera restoration, focus, clamped edges, invalid targets, errors and native fallback passed")
