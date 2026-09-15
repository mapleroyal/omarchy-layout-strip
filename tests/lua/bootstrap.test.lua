local base=arg[1] or 'backend/'
local Bootstrap=dofile(base..'tape-bootstrap.lua')
local timers,listeners,finished={},{},{}
local hl={dsp={cursor={}}}
local cursor={x=1500,y=0}
local no_warps=false
function hl.get_cursor_pos() return {x=cursor.x,y=cursor.y} end
function hl.get_config(key) assert(key=='cursor.no_warps');return no_warps end
function hl.config(value) no_warps=value.cursor.no_warps end
function hl.dsp.cursor.move(args) return args end
function hl.dispatch(args) cursor={x=args.x,y=args.y};return {ok=true} end
function hl.timer(callback,options)
  local timer={enabled=true,callback=callback}
  function timer:set_enabled(value) self.enabled=value end
  function timer:is_enabled() return self.enabled end
  function timer:set_timeout(value) self.enabled=true;self.timeout=value end
  timers[#timers+1]=timer
  return timer
end
function hl.on(name,callback)
  local listener={callback=callback,active=true}
  function listener:remove() self.active=false end
  listeners[#listeners+1]=listener
  return listener
end
local tape={}
function tape.prepare_close(w,previous)
  return previous or {workspace_id=w.workspace.id}
end
function tape.prepare_fullscreen_exit(w) return {workspace_id=w.workspace.id} end
function tape.finish_close(token) finished[#finished+1]='close'..token.workspace_id;return {ok=true,changed=false} end
function tape.finish_fullscreen_exit(token) finished[#finished+1]='full'..token.workspace_id;return {ok=true,changed=false} end
local Bar={new=function() return {protocol_version=2} end}
local one,two={workspace={id=1},fullscreen=0},{workspace={id=2},fullscreen=0}
local integration=Bootstrap.new(hl,tape,Bar)
assert(not timers[1].enabled and not timers[2].enabled)
-- Consecutive bar scrolls focus their columns with the native warp suppressed.
-- Restore the user's warp preference for keyboard navigation, even on errors.
local browsed=0
function tape.browse_monitor(direction,monitor)
  assert(direction=='l' or direction=='r')
  assert(monitor=='screen')
  browsed=browsed+1
  if not no_warps then cursor={x=800,y=600} end
  return {ok=true,changed=true}
end
for _,direction in ipairs({'l','r','l'}) do
  assert(integration.browse_from_bar(direction,'screen').ok)
  assert(cursor.x==1500 and cursor.y==0 and no_warps==false)
  timers[1].callback()
  assert(cursor.x==1500 and cursor.y==0)
end
assert(browsed==3)
no_warps=true
assert(integration.browse_from_bar('r','screen').ok and no_warps==true)
no_warps=false
tape.browse_monitor=function() error('focus failed') end
local ok,reason=pcall(integration.browse_from_bar,'r','screen')
assert(not ok and reason:find('focus failed',1,true) and no_warps==false)
tape.browse_monitor=function() return {ok=false,error='stale monitor'} end
assert(not integration.browse_from_bar('r','screen').ok and no_warps==false)
timers[1].callback()
listeners[1].callback(one);listeners[1].callback(two)
assert(timers[2].enabled)
timers[2].callback()
assert(#finished==2 and not timers[2].enabled)
timers[2].callback();assert(#finished==2)
-- Discrete gesture deferral must suppress capture and pending timer repairs.
integration.begin_pointer_refocus_deferral()
listeners[1].callback(one)
assert(not timers[2].enabled)
listeners[2].callback(one)
assert(timers[2].enabled)
timers[2].callback();assert(#finished==2)
integration.flush_pointer_refocus()
listeners[1].callback(one)
integration.begin_pointer_refocus_deferral()
timers[2].callback();assert(#finished==2)
integration.flush_pointer_refocus()
-- Replacing bootstrap removes old subscriptions and leaves stale callbacks inert.
listeners[1].callback(one)
local old=integration
integration=Bootstrap.new(hl,tape,Bar)
assert(not listeners[1].active and not listeners[2].active)
assert(not timers[1].enabled and not timers[2].enabled)
listeners[1].callback(one);timers[2].callback();old.finish_navigation({ok=true})
assert(#finished==2 and not timers[1].enabled and not timers[2].enabled)
old.dispose();old.dispose()
assert(not old.browse_from_bar('r','screen').ok and no_warps==false)
integration.dispose();integration.dispose()
assert(not listeners[3].active and not listeners[4].active and not timers[3].enabled and not timers[4].enabled)
print('Bootstrap independent repair queues, gesture deferral, one-shot timer, replacement and idempotent disposal passed')
