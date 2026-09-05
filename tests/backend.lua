local backend = dofile('backend/tape-bar.lua')
local tape_module = dofile('backend/tape.lua')
local monitors, windows, active, dispatched = {}, {}, nil, {}
local workspace = { id = 1, name = '1', tiled_layout = 'scrolling' }
local monitor = { id = 0, name = 'test-1', active_workspace = workspace }
workspace.monitor = monitor
monitors[1] = monitor
local hl = {
  get_monitors = function() return monitors end,
  get_active_special_workspace = function() return nil end,
  get_active_workspace = function() return workspace end,
  get_active_window = function() return active end,
  get_workspace_windows = function(ws) return ws == workspace and windows or {} end,
  get_config = function() return true end,
  dispatch = function(action) dispatched[#dispatched + 1] = action; return {ok = true} end,
  dsp = {focus = function(args) return args end},
}
local tape = tape_module.new(hl)
local bar = backend.new(hl, tape, function(result) return result end)
local function window(address, index, width, extra)
  local w = { address=address, mapped=true, hidden=false, floating=false,
    class='test', title='sample', fullscreen=0, workspace=workspace,
    layout={name='scrolling', column={index=index, width=width}} }
  for key,value in pairs(extra or {}) do w[key] = value end
  return w
end
assert(bar.snapshot('missing'):find('"columns":%[%]'))
windows = {window('0x2', 1, 0.667), window('0x1', 0, 0.5),
           window('0x3', 2, 1, {floating=true}), window('0x4', 0, 0.5)}
active = windows[4]
local snapshot = bar.snapshot('test-1')
assert(snapshot:find('"address":"0x4"')) -- focused stack member wins
assert(not snapshot:find('"address":"0x1"'))
assert(not snapshot:find('"address":"0x3"')) -- floating is absent
assert(snapshot:find('"address":"0x4"') < snapshot:find('"address":"0x2"'))
assert(snapshot:find('"size":"small"') and snapshot:find('"size":"medium"'))
assert(not tape.jump('0x2', 99, 'test-1').ok)
assert(not tape.jump('0x2', 1, 'missing').ok)
assert(not tape.jump('0x3', 1, 'test-1').ok)
assert(#dispatched == 0) -- stale and floating targets do not focus
local focus = tape.jump('0x2', 1, 'test-1')
assert(focus.ok and focus.aligned == false and #dispatched == 1)
assert(dispatched[1].window == windows[1])
windows = {windows[2]}
assert(bar.snapshot('test-1'):find('"size":"large"')) -- effective solo width
workspace.tiled_layout = 'dwindle'
assert(bar.snapshot('test-1'):find('"columns":%[%]'))
print('14 backend checks passed')
