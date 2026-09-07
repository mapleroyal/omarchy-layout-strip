-- Exercises installed Lua coordination with two independent mocked native cameras.
local base=arg[1] or 'backend/'
local Tape=dofile(base..'tape.lua')
local Bar=dofile(base..'tape-bar.lua')
local monitors={{id=0,name='one'},{id=1,name='two'}}
local spaces,windows,cameras={},{},{[1]=600,[2]=600}
for i,monitor in ipairs(monitors) do
  spaces[i]={id=i,name=tostring(i),monitor=monitor,tiled_layout='scrolling'}
  monitor.active_workspace=spaces[i]
  windows[i]={}
  for j=1,5 do
    local w={address=string.format('0x%x',i*16+j),mapped=true,hidden=false,floating=false,fullscreen=0,workspace=spaces[i]}
    w.layout={name='scrolling',column={index=j-1,width=.5,windows={w}}}
    windows[i][j]=w
  end
end
local current,active=spaces[2],windows[2][3]
local calls,dispatched={},{ }
local native={}
function native.info() return {ok=true,protocolVersion=2,addressedCamera=true,ownedRegions=true,reorder=true} end
function native.snapshot(id,monitor)
  id=id or current.id
  if monitor and spaces[id].monitor.name~=monitor then return {ok=false} end
  if not monitor and active and active.floating then return {ok=false} end
  return {ok=true,offset=cameras[id],width=1200}
end
function native.pan(delta,exact,id,monitor)
  id=id or current.id
  if monitor and spaces[id].monitor.name~=monitor then return {ok=false} end
  cameras[id]=cameras[id]-delta
  calls[#calls+1]={id=id,delta=delta}
  return {ok=true}
end
local hl={plugin={tape=native},dsp={}}
function hl.get_active_workspace() return current end
function hl.get_active_special_workspace() return nil end
function hl.get_active_window() return active end
function hl.get_workspace_windows(s) return windows[s.id] end
function hl.get_monitors() return monitors end
function hl.get_config() return false end
function hl.dsp.layout(command) return {command=command} end
function hl.dsp.focus(args) return {focus=args.window} end
function hl.dispatch(action)
  dispatched[#dispatched+1]=action
  if action.focus then active=action.focus;current=active.workspace end
  return {ok=true}
end
local tape=Tape.new(hl)
local bar=Bar.new(hl,tape,function(r) return r end)
local function remove(i,j)
  table.remove(windows[i],j)
  for index,w in ipairs(windows[i]) do w.layout.column.index=index-1 end
end
local target=windows[1][1]
local token=tape.prepare_close(target)
assert(token and token.workspace_id==1 and token.offscreen)
remove(1,1)
local r=tape.finish_close(token)
assert(r.ok and r.changed and cameras[1]==0 and cameras[2]==600)
assert(active==windows[2][3] and #dispatched==0,'cross-monitor repair must never activate target workspace')
local before=#calls
assert(tape.finish_close(token).changed==false and #calls==before,'tokens are consumed once')
-- Floating focus on the target output still allows addressed repair.
current=spaces[1]
active={address='0xff',floating=true,mapped=true,fullscreen=0,workspace=current}
cameras[1]=600
assert(tape.snapshot()==nil)
token=tape.prepare_close(windows[1][1])
assert(token and token.offscreen)
remove(1,1)
r=tape.finish_close(token)
assert(r.ok and cameras[1]==0 and active.address=='0xff' and #dispatched==0)
-- A close burst on both outputs keeps independent generations/cameras.
cameras[1],cameras[2]=600,600
local first=tape.prepare_close(windows[1][1])
local second=tape.prepare_close(windows[2][1])
remove(1,1);remove(2,1)
assert(tape.finish_close(first).ok and tape.finish_close(second).ok)
assert(cameras[1]==0 and cameras[2]==0)
-- Accepted reorder invalidates same-workspace close tokens only.
cameras[2]=600
local stale=tape.prepare_close(windows[2][1])
function native.reorder() return {ok=true,changed=true} end
assert(bar.reorder(windows[2][1].address,windows[2][2].address,'after',2,'two'):find('"ok":true',1,true))
before=#calls
assert(tape.finish_close(stale).changed==false and #calls==before)
-- Rejected and no-op reorder preserve the pending repair's authority.
for _,reply in ipairs({{ok=false,error='busy'},{ok=true,changed=false}}) do
  local pending=tape.prepare_close(windows[2][1])
  function native.reorder() return reply end
  bar.reorder(windows[2][1].address,windows[2][2].address,'after',2,'two')
  assert(pending.generation==tape.prepare_close(windows[2][1]).generation)
end
-- A monitor/workspace switch invalidates the addressed repair context.
local pending=tape.prepare_close(windows[2][1])
monitors[2].active_workspace=nil
before=#calls
assert(tape.finish_close(pending).changed==false and #calls==before)
monitors[2].active_workspace=spaces[2]
-- Case-normalized focus matches canonical lowercase compositor addresses.
current=spaces[2];active=windows[2][1]
windows[2][2].address='0xab'
r=tape.jump('0xAB',2,'two')
assert(r.ok and active.address=='0xab')
-- Multiple closes before a timer preserve earliest context and exclude every
-- removed target instead of replacing one workspace's token with another.
cameras[2]=1200
local first_target,second_target=windows[2][1],windows[2][2]
local burst=tape.prepare_close(first_target)
remove(2,1);cameras[2]=600
assert(tape.prepare_close(second_target,burst)==burst)
assert(burst.excluded[first_target.address] and burst.excluded[second_target.address])
remove(2,1);cameras[2]=0
assert(tape.finish_close(burst).ok and cameras[2]==0)
-- Snapshot v2 response and owned-region batch are independently callable.
assert(bar.protocol_version==2)
local bulk=bar.snapshot_all({'one','two'})
assert(bulk:find('"protocolVersion":2',1,true) and bulk:find('"snapshots":[',1,true))
local owners={}
function native.protect_bar_region(m,x,y,w,h,owner)
  owners[#owners+1]=owner
  return {ok=true}
end
assert(bar.protect_regions({{monitor='one',x=0,y=0,width=100,height=26}},'owner-v2'):find('"ok":true',1,true))
assert(owners[1]=='owner-v2')
assert(bar.protect_region('one',0,0,100,26,nil):find('"ok":false',1,true))
print('Workspace-addressed repair, floating focus, one-shot tokens, per-workspace generation, stale context, casing and v2 batches passed')
