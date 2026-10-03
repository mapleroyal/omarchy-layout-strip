-- Snapshots use compositor-owned membership and never depend on cycle helpers
-- for window presence. This fixture does not touch the login compositor.
local Bar = dofile((arg[1] or "backend/") .. "tape-bar.lua")
local monitor = {id=0,name="portrait",width=1080,height=1920,scale=1,reserved={top=26}}
local workspace = {id=7,name="7",tiled_layout="scrolling",monitor=monitor}
monitor.active_workspace = workspace
local windows, active, cycles, calls = {}, nil, {}, {}
local hl = {plugin={tape={info=function() return {ok=true,protocolVersion=2,reorder=true} end,
  reorder=function(...) calls[#calls+1]={...}; return {ok=true} end}},dsp={window={}}}
function hl.get_monitors() return {monitor} end
function hl.get_active_window() return active end
function hl.get_workspace_windows() return windows end
function hl.get_config() return true end
function hl.dsp.focus(args) return {focus=args.window.address} end
function hl.dsp.window.close(args) return {close=args.window} end
function hl.dispatch(action) calls[#calls+1]=action; return {ok=true} end
function omarchy_window_width_cycle_state(window) return cycles[window.stable_id] end
local function new_bar()
  return Bar.new(hl,{available=function() return true end,
    invalidate_workspace=function() end,
    jump=function(address) calls[#calls+1]={jump=address}; return {ok=true} end},function(result) return result end)
end
local bar = new_bar()
local function window(id, column, row)
  return {address="0x"..id,stable_id=id,mapped=true,hidden=false,floating=column==nil,
    class="app"..id,title="Window "..id,fullscreen=0,workspace=workspace,size={x=540,y=800},
    layout=column and {name="scrolling",column={index=column,width=0.5},index_in_column=row or 0}}
end
-- Fixtures only use plain strings. Strip nested member arrays before reading
-- top-level fields so key iteration order cannot affect the assertions.
local function fields(text)
  local result = {}
  for key,value in text:gmatch('"(%w+)":"([^"]*)"') do result[key]=value end
  for key,value in text:gmatch('"(%w+)":([%d%.%-]+)') do result[key]=tonumber(value) end
  for key,value in text:gmatch('"(%w+)":(%a+)') do
    if value=="true" or value=="false" then result[key]=value=="true" end
  end
  return result
end
local function snapshot(target)
  local reply = (target or bar).snapshot("portrait")
  assert(reply:find('"ok":true',1,true),reply)
  local result={}
  for text in reply:match('"columns":(%b[])'):gmatch('%b{}') do
    local members = text:match('"members":(%b[])')
    local column = fields((text:gsub('"members":%b[]','')))
    column.members={}
    for member in members:gmatch('%b{}') do column.members[#column.members+1]=fields(member) end
    result[#result+1]=column
  end
  return result, reply
end
local function order(columns, expected)
  assert(#columns==#expected,"wrong column count")
  for i,address in ipairs(expected) do assert(columns[i].address==address,"wrong order at "..i) end
end
local function success(reply) assert(reply:find('"ok":true',1,true),reply) end

local a,b,c=window(1,0),window(2,1),window(3,2)
windows,active={a,b,c},b
local initial=snapshot()
local b_id=initial[2].columnId
cycles[2]={stage=1,floating=false,layout={name="scrolling",column={index=1,width=0.5}}}
b.floating,b.layout=true,nil
b.size.x=720
c.layout.column.index=1
local floated=snapshot()
order(floated,{"0x1","0x2","0x3"})
assert(floated[2].floating and floated[2].cycled and floated[2].columnId==b_id)
assert(floated[2].size=="medium" and floated[2].members[1].floating)

-- Opening and focusing another app must retain the float at its logical slot
-- even when its old index now belongs to a different native column.
local d=window(4,2)
windows,active={d,c,b,a},d
local opened=snapshot()
order(opened,{"0x1","0x2","0x3","0x4"})
assert(opened[2].columnId==b_id and not opened[2].focused)
cycles={}
local lost=snapshot()
order(lost,{"0x1","0x2","0x3","0x4"})
assert(lost[2].columnId==b_id and lost[2].floating and not lost[2].cycled)
success(bar.focus(b.address,7,"portrait"))
assert(calls[#calls].focus==b.address)
success(bar.close(b.address,7,"portrait"))
assert(calls[#calls].close=="address:"..b.address)
function omarchy_cycle_window_width(target,direction)
  assert(target==b and direction==1); return {ok=true}
end
success(bar.cycle_window(b.address,7,"portrait",1))
assert(not bar.cycle_width(b.address,7,"portrait"):find('"ok":true',1,true))
assert(not bar.reorder(b.address,a.address,"before",7,"portrait"):find('"ok":true',1,true))

-- Broken or malformed optional metadata must not hide an otherwise live app.
function omarchy_window_width_cycle_state() error("stale restoration helper") end
order(snapshot(),{"0x1","0x2","0x3","0x4"})
for _,malformed in ipairs({{layout=1},{layout={name="scrolling",column=2}},
  {layout={name="scrolling",column={index=0,width="bad"}}},
  {layout={name="scrolling",column={index=math.huge,width=0.5}}}}) do
  function omarchy_window_width_cycle_state() return malformed end
  assert(not snapshot()[2].cycled)
end

-- A reload forgets logical slots but must still enumerate and address floats.
omarchy_window_width_cycle_state=nil
local reloaded=new_bar()
local recovered=snapshot(reloaded)
order(recovered,{"0x1","0x3","0x4","0x2"})
local e=window(5,3)
windows,active={b,e,a,c,d},e
order(snapshot(reloaded),{"0x1","0x3","0x4","0x5","0x2"})
local recovered_id=snapshot(reloaded)[5].columnId
success(reloaded.focus(b.address,7,"portrait"))
assert(calls[#calls].focus==b.address)

-- A single tiled column stays full-width with a separate floating client;
-- float width is measured against logical monitor width, including rotation.
windows={a,b}
b.size.x=540
local single=snapshot(reloaded)
assert(single[1].width==1 and single[2].width==0.5)
monitor.width,monitor.height,monitor.transform,monitor.scale=1920,1080,1,2
b.size.x=270
single=snapshot(reloaded)
assert(single[2].width==0.5)
monitor.width,monitor.height,monitor.transform,monitor.scale=1080,1920,0,1

-- No stale identity survives close/address reuse, including reuse between polls.
windows={a}
snapshot(reloaded)
local replacement=window(22)
replacement.address=b.address
windows={a,replacement}
assert(snapshot(reloaded)[2].columnId~=recovered_id)
local replacement_id=snapshot(reloaded)[2].columnId
replacement.stable_id=23
assert(snapshot(reloaded)[2].columnId~=replacement_id)
replacement.hidden=true
assert(#snapshot(reloaded)==1)
replacement.hidden=false
replacement.mapped=false
assert(#snapshot(reloaded)==1)

-- Native row indices determine menu order independently of client enumeration.
bar=new_bar()
a,b,c=window(10,0,0),window(11,0,1),window(12,1,0)
windows,active={b,c,a},b
local stacked=snapshot()
assert(stacked[1].memberCount==2 and stacked[1].address==b.address)
assert(stacked[1].members[1].address==a.address and stacked[1].members[2].address==b.address)
local stack_id=stacked[1].columnId
active=a
stacked=snapshot()
assert(stacked[1].columnId==stack_id and stacked[1].address==a.address)
active=c
windows={a,b,c}
stacked=snapshot()
assert(stacked[1].columnId==stack_id and stacked[1].address==a.address and not stacked[1].focused)
success(bar.focus(b.address,7,"portrait"))
assert(calls[#calls].jump==b.address)

-- Reordering a stack preserves its identity and row ordering; a native split
-- gives each resulting column exactly one identity, and merge removes one.
a.layout.column.index,b.layout.column.index,c.layout.column.index=1,1,0
stacked=snapshot()
assert(stacked[2].columnId==stack_id)
a.layout.column.index,b.layout.column.index,c.layout.column.index=0,1,2
local split=snapshot()
assert(#split==3 and split[1].columnId~=split[2].columnId)
assert(split[1].columnId==stack_id)
b.layout.column.index=0
c.layout.column.index=1
stacked=snapshot()
assert(#stacked==2 and stacked[1].columnId==stack_id and stacked[1].memberCount==2)

-- Floating one stack member creates a separate tile beside the remaining real
-- column. Restoring that member merges its tile back into native membership.
b.floating,b.layout=true,nil
local detached=snapshot()
order(detached,{a.address,b.address,c.address})
assert(detached[1].columnId==stack_id and detached[1].memberCount==1)
assert(not detached[1].floating and detached[2].floating and detached[2].columnId~=stack_id)
b.floating,b.layout=false,{name="scrolling",column={index=0,width=0.5},index_in_column=1}
stacked=snapshot()
assert(#stacked==2 and stacked[1].columnId==stack_id and stacked[1].memberCount==2)
print("Bar snapshot contracts passed (floating presence, stable stacks and native ordering)")
