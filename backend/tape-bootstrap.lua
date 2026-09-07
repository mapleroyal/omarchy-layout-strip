-- The user bindings consume this narrow adapter. It owns bar RPCs, pointer
-- refresh and per-workspace lifecycle repairs; it installs no keybindings.
local M = {}
local active
function M.new(hl, tape, Bar)
  if active then active.dispose() end
  local self = {}
  local disposed = false
  local deferred, pending = false, false
  local refocus_timer
  local function refocus()
    if disposed then return end
    refocus_timer:set_enabled(false)
    local cursor = hl.get_cursor_pos()
    if cursor then hl.dispatch(hl.dsp.cursor.move({x=cursor.x,y=cursor.y})) end
  end
  refocus_timer = hl.timer(refocus,{timeout=50,type="repeat"})
  refocus_timer:set_enabled(false)
  function self.finish_navigation(result)
    if disposed then return result end
    if (not result or result.ok ~= false) and (not result or result.changed ~= false) then
      if deferred then pending=true
      else refocus(); refocus_timer:set_timeout(50) end
    end
    return result
  end
  function self.begin_pointer_refocus_deferral()
    if disposed then return end
    if refocus_timer:is_enabled() then pending=true; refocus_timer:set_enabled(false) end
    deferred=true
  end
  function self.flush_pointer_refocus()
    if disposed then return end
    deferred=false
    if pending then pending=false; refocus_timer:set_timeout(50) end
  end

  local close_tokens, fullscreen_tokens = {}, {}
  local repair_timer
  repair_timer = hl.timer(function()
    repair_timer:set_enabled(false)
    local closes, exits = close_tokens, fullscreen_tokens
    close_tokens, fullscreen_tokens = {}, {}
    if disposed or deferred then return end
    local function repair(method,token)
      local ok,result=pcall(method,token)
      if ok then self.finish_navigation(result)
      else print("Layout strip geometry repair failed: "..tostring(result)) end
    end
    for _, token in pairs(closes) do repair(tape.finish_close,token) end
    for _, token in pairs(exits) do repair(tape.finish_fullscreen_exit,token) end
  end,{timeout=1,type="repeat"})
  repair_timer:set_enabled(false)
  self.close_listener = hl.on("window.close",function(window)
    if disposed or deferred then return end
    local workspace = window and window.workspace
    if not workspace then return end
    local token = tape.prepare_close(window,close_tokens[workspace.id])
    if token then close_tokens[workspace.id]=token; repair_timer:set_timeout(1) end
  end)
  self.fullscreen_listener = hl.on("window.fullscreen",function(window)
    if disposed then return end
    if not window or window.fullscreen ~= 0 then return end
    local token = tape.prepare_fullscreen_exit(window)
    if token then fullscreen_tokens[token.workspace_id]=token; repair_timer:set_timeout(1) end
  end)
  self.bar = Bar.new(hl,tape,self.finish_navigation)
  -- Retain timers with the adapter for the whole config lifetime.
  self.refocus_timer, self.repair_timer = refocus_timer, repair_timer
  function self.dispose()
    if disposed then return end
    disposed=true
    refocus_timer:set_enabled(false)
    repair_timer:set_enabled(false)
    self.close_listener:remove()
    self.fullscreen_listener:remove()
    close_tokens, fullscreen_tokens = {}, {}
    if active == self then active=nil end
  end
  active=self
  return self
end
return M
