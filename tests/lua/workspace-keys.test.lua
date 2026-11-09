-- Actual 0.57 Lua object shape: named/special workspaces have no numeric id.
-- All compositor/native methods are fixtures; no live connection is used.
local base = arg[1] or "backend/"
local Tape, Bar, Bootstrap = dofile(base .. "tape.lua"), dofile(base .. "tape-bar.lua"), dofile(base .. "tape-bootstrap.lua")
local function key(workspace) return workspace.id or workspace.addressable_name end
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
for _, identity in ipairs({1, -99, "special:scratchpad", "special:qconsole", "name:Research"}) do
  local monitors = {{id=0,name="main"}, {id=1,name="portrait"}}
  local first = {name=tostring(identity),addressable_name=tostring(identity),monitor=monitors[1],tiled_layout="scrolling"}
  if type(identity) == "number" then first.id=identity end
  local second = {name="special:other",addressable_name="special:other",monitor=monitors[2],tiled_layout="scrolling"}
  monitors[1].active_special_workspace,monitors[2].active_special_workspace=first,second
  local spaces = {[identity]=first,[key(second)]=second}
  local windows,offsets = {},{[identity]=600,[key(second)]=600}
  for id,workspace in pairs(spaces) do
    windows[id]={}
    for i=1,5 do
      local w={address=string.format("0x%x",(workspace==first and 16 or 32)+i),workspace=workspace,
        mapped=true,hidden=false,floating=false,fullscreen=0}
      w.layout={name="scrolling",column={index=i-1,width=.5,windows={w}}}
      windows[id][i]=w
    end
  end
  local current,active=second,windows[key(second)][2]
  local native_calls,dispatches,timers,listeners={},{},{},{}
  local support_keys=true
  local native={}
  function native.info() return {ok=true,protocolVersion=2,addressedCamera=true,addressedResize=true,reorder=true,workspaceKeys=support_keys} end
  function native.snapshot(id,monitor)
    id=id or key(current)
    check(spaces[id] and (not monitor or spaces[id].monitor.name==monitor),"exact native snapshot context")
    return {ok=true,width=1200,offset=offsets[id],layoutFullscreen=true}
  end
  function native.pan(delta,exact,id,monitor)
    id=id or key(current)
    check(spaces[id] and (not monitor or spaces[id].monitor.name==monitor),"exact native pan context")
    offsets[id]=offsets[id]-delta;native_calls[#native_calls+1]={id=id,kind="pan"};return {ok=true,changed=true}
  end
  function native.reorder(a,b,side,id,monitor)
    check(id==identity and monitor=="main","reorder preserves actual key")
    native_calls[#native_calls+1]={id=id,kind="reorder"};return {ok=true,changed=true}
  end
  function native.resize_column(a,width,id,monitor)
    check(id==identity and monitor=="main","resize preserves actual key")
    native_calls[#native_calls+1]={id=id,kind="resize"};return {ok=true,changed=true}
  end
  local hl={plugin={tape=native},dsp={window={},cursor={}}}
  function hl.get_active_workspace() return nil end
  function hl.get_active_special_workspace() return current end
  function hl.get_active_window() return active end
  function hl.get_workspace_windows(workspace) return windows[key(workspace)] end
  function hl.get_monitors() return monitors end
  function hl.get_config() return false end
  function hl.get_cursor_pos() return nil end
  function hl.dsp.layout(command) return {command=command} end
  function hl.dsp.focus(args) return {focus=args.window} end
  function hl.dsp.window.close(args) return {close=args.window} end
  function hl.dispatch(action)
    dispatches[#dispatches+1]=action
    if action.focus then active=action.focus;current=active.workspace end
    return {ok=true,changed=true}
  end
  function hl.timer(callback)
    local t={callback=callback}
    function t:set_enabled(value) self.enabled=value end
    function t:is_enabled() return self.enabled end
    function t:set_timeout() self.enabled=true end
    timers[#timers+1]=t;return t
  end
  function hl.on(event,callback)
    listeners[event]=callback;return {remove=function() end}
  end
  local tape=Tape.new(hl)
  local bar=Bar.new(hl,tape,function(result) return result end)
  local snapshot=bar.snapshot("main")
  local encoded=type(identity)=="number" and tostring(identity) or '"'..identity..'"'
  check(snapshot:find('"workspaceId":'..encoded,1,true),"JSON preserves workspace number/string")
  check(snapshot:find('"columnId":"column:'..identity..':',1,true),"column identity has actual workspace key")
  local s=tape.snapshot(identity,"main")
  check(s and s.workspace_id==identity,"addressed camera accepts current workspace object")
  local token=tape.prepare_close(windows[identity][1])
  check(token and token.workspace_id==identity,"close repair token has actual key")
  table.remove(windows[identity],1)
  for i,w in ipairs(windows[identity]) do w.layout.column.index=i-1 end
  check(tape.finish_close(token).ok and offsets[identity]==0,"background close repairs correct camera")
  check(current==second and #dispatches==0,"background repair keeps other special workspace focused")
  check(tape.finish_close(token).changed==false,"close token consumed once")
  check(bar.reorder(windows[identity][1].address,windows[identity][2].address,"after",identity,"main"):find('"ok":true',1,true),"bar reorder works")
  check(bar.cycle_width(windows[identity][1].address,identity,"main"):find('"ok":true',1,true),"bar resize works")
  check(not bar.close(windows[identity][1].address,key(second),"main"):find('"ok":true',1,true),"other nil-id workspace rejected")
  check(tape.jump(windows[identity][2].address,identity,"main").ok and current==first,"jump distinguishes two nil-id workspaces")
  check(tape.browse_monitor("r","main").ok,"bar browse on special workspace works")
  local integration=Bootstrap.new(hl,tape,Bar)
  listeners["window.close"](windows[identity][1])
  check(timers[2].enabled,"close queue accepts string key")
  timers[2].callback()
  listeners["window.fullscreen"](windows[identity][1])
  check(timers[2].enabled,"fullscreen queue accepts string key")
  timers[2].callback()
  integration.dispose()
  if type(identity)=="string" then
    support_keys=false
    local before=#native_calls
    check(tape.snapshot(identity,"main")==nil,"old bridge rejects addressed strings before native call")
    check(not bar.reorder(windows[identity][1].address,windows[identity][2].address,"after",identity,"main"):find('"ok":true',1,true),"old bridge rejects string reorder")
    check(not bar.cycle_width(windows[identity][1].address,identity,"main"):find('"ok":true',1,true),"old bridge rejects string resize")
    check(#native_calls==before,"unsupported string context never mutates native state")
    check(tape.snapshot()~=nil,"ordinary active-camera path survives old bridge")
  end
end
print("PASS: "..checks.." workspace-key checks across numbered, legacy-special, scratchpad, qconsole and named workspaces")
