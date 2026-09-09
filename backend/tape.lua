-- Shared column geometry for keyboard steps and finger-following browsing.
-- The small native bridge exposes the scrolling layout's own camera. It does
-- not implement another layout or animation system.
local M = {}
local G = {}
M.geometry = G

local EPS = 2 -- Native layout boxes are rounded to logical pixels.
local function clamp(value, low, high)
  return math.max(low, math.min(value, high))
end
local function noop()
  return { ok = true, changed = false }
end
local function failed(result)
  return result and result.ok == false
end

function G.build(widths, viewport, offset, fullscreen_on_one)
  local s = { width = viewport, offset = offset, columns = {}, extent = 0 }
  for i, width in ipairs(widths) do
    local size = (#widths == 1 and fullscreen_on_one) and viewport or width * viewport
    s.columns[i] = { index = i - 1, width = width, start = s.extent, size = size,
      finish = s.extent + size }
    s.extent = s.extent + size
  end
  s.minimum = s.extent < viewport and math.floor((s.extent - viewport) / 2 + 0.5) or 0
  s.maximum = math.max(s.minimum, s.extent - viewport)
  return s
end

function G.clamp(s, offset)
  return clamp(offset, s.minimum, s.maximum)
end

-- Both edges of every column are meaningful resting positions. In particular,
-- moving a visible half column to the left can reveal part of its wide neighbor.
-- Logical column strips, rather than client borders/gaps, define these stops.
function G.stops(s)
  local stops = {}
  local function add(offset, low, high)
    offset = G.clamp(s, offset)
    stops[#stops + 1] = { offset = offset,
      low = G.clamp(s, low or offset), high = G.clamp(s, high or offset) }
  end
  add(s.minimum)
  add(s.maximum)
  for _, column in ipairs(s.columns) do
    local left, right = column.start, column.finish - s.width
    if column.size >= s.width * 0.96 and column.size <= s.width + EPS then
      -- A nearly full-width column has a small alignment range. Treat that
      -- range as one view, preserving intentional peeks without tiny steps.
      add((left + right) / 2, math.min(left, right), math.max(left, right))
    else
      add(left)
      add(right)
    end
  end
  table.sort(stops, function(a, b) return a.offset < b.offset end)
  local unique = {}
  for _, stop in ipairs(stops) do
    local previous = unique[#unique]
    if previous and math.abs(stop.offset - previous.offset) <= EPS then
      previous.low = math.min(previous.low, stop.low)
      previous.high = math.max(previous.high, stop.high)
    else
      unique[#unique + 1] = stop
    end
  end
  return unique
end

local function within_stop(stop, offset)
  return offset >= stop.low - EPS and offset <= stop.high + EPS
end

local function landing_column(s, offset, direction)
  local chosen
  for i, column in ipairs(s.columns) do
    if column.start >= offset - EPS and column.finish <= offset + s.width + EPS then
      if not chosen or direction == "r" then chosen = i end
    end
  end
  if chosen then return chosen end
  -- Oversized columns can expose either edge without fitting in the viewport.
  for i, column in ipairs(s.columns) do
    if column.finish > offset + EPS and column.start < offset + s.width - EPS then
      if not chosen or direction == "r" then chosen = i end
    end
  end
  return chosen
end

function G.next(s, direction, edge, offset)
  offset = offset or s.offset
  if #s.columns == 0 then return nil end
  if edge then
    local index = direction == "l" and 1 or #s.columns
    local target = direction == "l" and s.minimum or s.maximum
    if math.abs(target - offset) <= EPS then return nil end
    return target, index
  end
  if s.extent <= s.width + EPS then return nil end
  local stops = G.stops(s)
  for step = 1, #stops do
    local stop = stops[direction == "l" and (#stops - step + 1) or step]
    local forward = direction == "l" and stop.offset < offset - EPS
      or direction == "r" and stop.offset > offset + EPS
    if forward and not within_stop(stop, offset) then
      return stop.offset, landing_column(s, stop.offset, direction)
    end
  end
  return nil
end

function G.half(s, index, direction)
  if not s.columns[index] then return nil end
  -- An endpoint rejection is a complete no-op, including size and focus.
  if (direction == "l" and index == #s.columns) or (direction == "r" and index == 1) then
    return nil
  end
  if direction ~= "l" and direction ~= "r" then return nil end
  return s.columns[index].start - (direction == "r" and s.width / 2 or 0)
end

-- Release position chooses the nearest resting view; speed cannot fling past
-- the column the user has brought into place. A short monotonic swipe can still
-- advance one stop, but a deliberate backtrack disables that convenience.
function G.land(s, position, displacement, allow_advance)
  if math.abs(displacement) <= EPS or s.extent <= s.width + EPS then return s.offset end
  local direction = displacement > 0 and "r" or "l"
  local best = s.offset
  for _, stop in ipairs(G.stops(s)) do
    if not within_stop(stop, s.offset)
      and math.abs(stop.offset - position) < math.abs(best - position) then
      best = stop.offset
    end
  end
  if best == s.offset and allow_advance ~= false and math.abs(displacement) >= 80 then
    best = G.next(s, direction) or best
  end
  return best, best ~= s.offset and landing_column(s, best, direction) or nil
end

function M.new(hl)
  local self = {}
  local gesture
  local generations = {}
  local function current_workspace()
    return hl.get_active_special_workspace() or hl.get_active_workspace()
  end
  local function generation(workspace_id) return generations[workspace_id] or 0 end
  function self.invalidate_workspace(workspace_id)
    local workspace = not workspace_id and current_workspace() or nil
    workspace_id = workspace_id or (workspace and workspace.id)
    if workspace_id then generations[workspace_id] = generation(workspace_id) + 1 end
    if gesture and gesture.initial and gesture.initial.workspace_id == workspace_id then gesture = nil end
  end
  local function displayed_workspace(workspace_id, monitor_name)
    for _, monitor in ipairs(hl.get_monitors()) do
      local workspace = monitor.active_special_workspace or monitor.active_workspace
      if workspace and workspace.id == workspace_id and monitor.name == monitor_name then return workspace end
    end
  end

  local function bridge()
    return hl.plugin and hl.plugin.tape
  end

  local function layout(command)
    return hl.dispatch(hl.dsp.layout(command))
  end

  function self.available()
    local native = bridge()
    return native ~= nil and type(native.pan) == "function" and type(native.snapshot) == "function"
  end

  function self.snapshot(workspace_id, monitor_name)
    local addressed = workspace_id ~= nil
    local workspace = addressed and displayed_workspace(workspace_id, monitor_name) or (not addressed and current_workspace())
    if not workspace or workspace.tiled_layout ~= "scrolling" then return nil end
    local native = bridge()
    if not self.available() then return nil end
    if addressed then
      local ok, info = pcall(function() return native.info and native.info() end)
      if not ok or type(info) ~= "table" or info.protocolVersion ~= 2 or info.addressedCamera ~= true then return nil end
    end
    local camera = addressed and native.snapshot(workspace.id, monitor_name) or native.snapshot()
    if not camera or camera.ok == false or not camera.width or camera.width <= 0 or camera.offset == nil then return nil end
    local columns, indexes = {}, {}
    local active = hl.get_active_window()
    if active and active.workspace and active.workspace.id == workspace.id and active.fullscreen ~= 0 then return nil end
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      local info = window.layout
      local column = info and info.name == "scrolling" and info.column
      if window.mapped and not window.hidden and not window.floating and column and column.index ~= nil
        and not indexes[column.index] then
        indexes[column.index] = true
        columns[#columns + 1] = { index = column.index, width = column.width, window = window,
          windows = column.windows or { window } }
      end
    end
    table.sort(columns, function(a, b) return a.index < b.index end)
    if #columns == 0 then return nil end
    local widths = {}
    for i, column in ipairs(columns) do widths[i] = column.width end
    local s = G.build(widths, camera.width, camera.offset, hl.get_config("scrolling.fullscreen_on_one_column"))
    s.workspace, s.active = workspace, active
    s.workspace_id = workspace.id
    s.monitor = workspace.monitor
    s.monitor_id = s.monitor and s.monitor.id
    s.monitor_name = s.monitor and s.monitor.name
    s.addressed = addressed
    s.camera = camera
    for i, column in ipairs(columns) do
      local geometry = s.columns[i]
      geometry.index, geometry.window, geometry.windows = column.index, column.window, column.windows
      for _, window in ipairs(column.windows) do
        if active and window.address == active.address then s.active_index = i; geometry.window = active end
      end
    end
    return s
  end

  local function focus_without_pan(window)
    if not window or not window.mapped then return noop() end
    local active = hl.get_active_window()
    if active and active.address == window.address then return noop() end
    local result = layout("inhibit_scroll 1")
    if failed(result) then return result end
    -- Inhibition belongs to this synchronous action only, never the lifetime
    -- of a gesture or a timer. Always release it even if the focus call errors.
    local ok, focused = pcall(function() return hl.dispatch(hl.dsp.focus({ window = window })) end)
    local restored = layout("inhibit_scroll 0")
    if not ok then error(focused, 0) end
    return failed(focused) and focused or restored
  end

  local function pan_to(s, offset, window, exact_half, direct)
    local native = bridge()
    if not native or not s then return noop() end
    if not exact_half then offset = G.clamp(s, offset) end
    local delta = s.offset - offset
    local changed = math.abs(delta) > 0.5
    local result = noop()
    if changed then
      -- Only in-progress finger tracking bypasses native easing. Older bridges
      -- keep their previous behavior, including during an upgrade or rollback.
      local pan = direct and type(native.pan_direct) == "function" and native.pan_direct or native.pan
      result = s.addressed and pan(delta, exact_half == true, s.workspace_id, s.monitor_name)
        or pan(delta, exact_half == true)
    end
    if failed(result) then return result end
    if window then
      local active = hl.get_active_window()
      local focus_changed = not active or active.address ~= window.address
      result = focus_without_pan(window)
      if failed(result) then return result end
      changed = changed or focus_changed
    end
    return { ok = true, changed = changed }
  end

  local function native_focus(direction, edge)
    if edge then
      local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
      local chosen, chosen_index
      if workspace and workspace.tiled_layout == "scrolling" then
        for _, window in ipairs(hl.get_workspace_windows(workspace)) do
          local info = window.layout
          local column = info and info.name == "scrolling" and info.column
          if window.mapped and not window.hidden and column and column.index ~= nil then
            if chosen_index == nil or (direction == "l" and column.index < chosen_index)
              or (direction == "r" and column.index > chosen_index) then
              chosen, chosen_index = window, column.index
            end
          end
        end
      end
      if chosen then return hl.dispatch(hl.dsp.focus({ window = chosen })) end
    end
    return hl.dispatch(hl.dsp.focus({ direction = direction }))
  end

  function self.browse(direction, edge)
    self.invalidate_workspace()
    local s = self.snapshot()
    if not s then
      -- Keep the regular native controls useful if an update disables the
      -- optional bridge. Exact camera control is available only with it loaded.
      return native_focus(direction, edge)
    end
    local offset, index = G.next(s, direction, edge)
    if not offset then return noop() end
    return pan_to(s, offset, s.columns[index].window)
  end

  function self.focus(direction, edge)
    self.invalidate_workspace()
    local s = self.snapshot()
    if not s or not s.active_index then return native_focus(direction, edge) end
    local index = s.active_index
    local active = s.columns[index]
    if edge then
      index = direction == "l" and 1 or #s.columns
    elseif direction == "l" and active.start < s.offset - EPS then
      return pan_to(s, active.start, active.window)
    elseif direction == "r" and active.finish > s.offset + s.width + EPS then
      return pan_to(s, active.finish - s.width, active.window)
    else
      index = index + (direction == "l" and -1 or 1)
    end
    local column = s.columns[index]
    if not column then return noop() end
    local target = s.offset
    if edge then target = direction == "l" and s.minimum or s.maximum
    elseif column.start < s.offset then target = column.start
    elseif column.finish > s.offset + s.width then target = column.finish - s.width end
    return pan_to(s, target, column.window,
      math.abs(target - s.offset) <= EPS and (target < s.minimum or target > s.maximum))
  end

  -- Bar navigation targets a stable window address, never a cached column
  -- number. Only a workspace currently displayed on a monitor may be selected.
  function self.jump(address, workspace_id, monitor_name)
    if type(address) ~= "string" or not address:match("^0x%x+$") then return {ok=false,error="Invalid window address"} end
    address = address:lower()
    local current = hl.get_active_special_workspace() or hl.get_active_workspace()
    local workspace = current
    if monitor_name or (workspace_id and (not current or current.id ~= workspace_id)) then
      workspace = nil
      for _, monitor in ipairs(hl.get_monitors()) do
        local candidate = monitor.active_special_workspace or monitor.active_workspace
        if candidate and (not monitor_name or monitor.name == monitor_name)
          and (not workspace_id or candidate.id == workspace_id) then
          workspace = candidate
          break
        end
      end
    end
    if not workspace or (workspace_id and workspace.id ~= workspace_id)
      or workspace.tiled_layout ~= "scrolling" then
      return { ok = false, error = "The displayed scrolling workspace changed" }
    end
    local selected
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      if window.address:lower() == address and window.mapped and not window.hidden and not window.floating then
        selected = window
        break
      end
    end
    if not selected then return { ok = false, error = "The selected window is no longer tiled here" } end
    self.invalidate_workspace(workspace.id)

    local s = current and current.id == workspace.id and self.snapshot() or nil
    local focus_changed = false
    if not s then
      -- Focusing another monitor (or leaving a floating window) establishes
      -- the camera's workspace. Both operations finish in this same Lua call.
      local active = hl.get_active_window()
      focus_changed = not active or active.address ~= selected.address
      local result = hl.dispatch(hl.dsp.focus({ window = selected }))
      if failed(result) then return result end
      s = self.snapshot()
      -- Real fullscreen and an unavailable bridge keep native focus behavior.
      if not s then return { ok = true, changed = focus_changed, aligned = false } end
    end
    for _, column in ipairs(s.columns) do
      for _, window in ipairs(column.windows) do
        if window.address:lower() == address then
          local result = pan_to(s, column.start, selected)
          if not failed(result) then
            result.aligned = true
            result.changed = result.changed or focus_changed
          end
          return result
        end
      end
    end
    return { ok = false, error = "The selected scrolling column changed" }
  end

  function self.place_half(direction)
    self.invalidate_workspace()
    local before = self.snapshot()
    if not before or not before.active_index then return noop() end
    local index = before.active_index
    if G.half(before, index, direction) == nil then return noop() end
    if before.active and before.active.fullscreen ~= 0 then return noop() end
    local result = layout("colresize 0.5")
    if failed(result) then return result end
    local after = self.snapshot()
    if not after or after.workspace_id ~= before.workspace_id then return result end
    local target = G.half(after, after.active_index or index, direction)
    if target == nil then return result end
    result = pan_to(after, target, before.active, true)
    if not failed(result) then result.changed = true end
    return result
  end

  function self.normalize(workspace_id, monitor_name)
    self.invalidate_workspace(workspace_id)
    local s = self.snapshot(workspace_id, monitor_name)
    if not s then return noop() end
    local target = G.clamp(s, s.offset)
    if math.abs(target - s.offset) <= EPS then return noop() end
    return pan_to(s, target)
  end

  function self.resize(width)
    self.invalidate_workspace()
    local active = hl.get_active_window()
    local info = active and active.layout
    if not info or info.name ~= "scrolling" or not info.column or active.fullscreen ~= 0 then return noop() end
    local result = layout("colresize " .. tostring(width))
    if failed(result) then return result end
    result = self.normalize()
    if not failed(result) then result.changed = true end
    return result
  end

  function self.smooth_begin(event)
    self.invalidate_workspace()
    gesture = nil
    local s = self.snapshot()
    if not s then
      gesture = { fallback = true, displacement = 0 }
      return noop()
    end
    local native = bridge()
    local origin = s.offset
    if type(native.pan_direct) == "function" and s.extent > s.width + EPS
      and type(s.camera.renderedOffset) == "number" then
      origin = s.camera.renderedOffset
      -- Grab an unfinished snap at its visible position. Keep the original
      -- resting snapshot for release/cancel, and measure only finger movement
      -- as displacement (not the remaining distance of the interrupted snap).
      local result = pan_to(s, origin, nil, origin < s.minimum or origin > s.maximum, true)
      if failed(result) then return result end
    end
    gesture = { initial = s, current = origin, origin = origin, displacement = 0,
      peak = 0, direction = nil, backtracked = false }
    return noop()
  end

  local function same_columns(a, b)
    if a.workspace_id ~= b.workspace_id or a.monitor_id ~= b.monitor_id
      or math.abs(a.width - b.width) > EPS or #a.columns ~= #b.columns then return false end
    for i, column in ipairs(a.columns) do
      local other = b.columns[i]
      if math.abs(column.width - other.width) > 0.00001 or #column.windows ~= #other.windows then return false end
      local members = {}
      for _, member in ipairs(column.windows) do members[member.address] = true end
      for _, member in ipairs(other.windows) do if not members[member.address] then return false end end
    end
    return true
  end

  function self.smooth_update(event)
    if not gesture then return noop() end
    if gesture.fallback then
      gesture.displacement = gesture.displacement - (event.delta and event.delta.x or 0)
      return noop()
    end
    local s = self.snapshot()
    if not s or not same_columns(s, gesture.initial) then
      gesture = nil
      return noop()
    end
    if gesture.initial.extent <= gesture.initial.width + EPS then return noop() end
    local delta = -(event.delta and event.delta.x or 0)
    -- A deliberate half placement can leave a little empty space when its
    -- neighbor is narrower than half. Do not erase that choice by moving in
    -- the blocked direction or cancelling a subsequent gesture.
    local position = clamp(gesture.current + delta,
      math.min(s.minimum, gesture.initial.offset, gesture.origin),
      math.max(s.maximum, gesture.initial.offset, gesture.origin))
    gesture.current = position
    gesture.displacement = position - gesture.origin
    if not gesture.direction and math.abs(gesture.displacement) > EPS then
      gesture.direction = gesture.displacement > 0 and 1 or -1
    end
    if gesture.direction then
      local progress = gesture.displacement * gesture.direction
      gesture.peak = math.max(gesture.peak, progress)
      if gesture.peak - progress >= 12 then gesture.backtracked = true end
    end
    return pan_to(s, position, nil, position < s.minimum or position > s.maximum, true)
  end

  function self.smooth_end(event)
    local previous = gesture
    gesture = nil
    if not previous then return noop() end
    if previous.fallback then
      if (event and event.cancelled) or math.abs(previous.displacement) <= EPS then return noop() end
      return self.browse(previous.displacement > 0 and "r" or "l", false)
    end
    local s = self.snapshot()
    if not s or not same_columns(s, previous.initial) then return noop() end
    if event and event.cancelled then return pan_to(s, previous.initial.offset, previous.initial.active, true) end
    local target, index = G.land(previous.initial, previous.current, previous.displacement, not previous.backtracked)
    local window = index and s.columns[index] and s.columns[index].window or previous.initial.active
    return pan_to(s, target, window, target < s.minimum or target > s.maximum)
  end

  -- A fullscreen exit is a native geometry change, not an explicit half
  -- placement. Normalize only that workspace after the native transition has
  -- settled, without stealing focus or overriding a subsequent tape action.
  local function fullscreen_exit_workspace(window)
    if not window or not window.mapped or window.floating or window.fullscreen ~= 0 then return nil end
    local workspace = window.workspace
    local info = window.layout
    if not workspace or not workspace.monitor or workspace.tiled_layout ~= "scrolling" or not info
      or info.name ~= "scrolling" or not info.column
      or not displayed_workspace(workspace.id, workspace.monitor.name) then return nil end
    return workspace
  end

  function self.prepare_fullscreen_exit(window)
    local workspace = fullscreen_exit_workspace(window)
    if not workspace or (gesture and gesture.initial and gesture.initial.workspace_id == workspace.id) then return nil end
    return {generation=generation(workspace.id), workspace_id=workspace.id, monitor_name=workspace.monitor.name, window=window}
  end

  function self.finish_fullscreen_exit(token)
    if not token or token.generation ~= generation(token.workspace_id) then return noop() end
    local workspace = fullscreen_exit_workspace(token.window)
    if not workspace or workspace.id ~= token.workspace_id then return noop() end
    return self.normalize(token.workspace_id, token.monitor_name)
  end

  -- A close may target any displayed output while keyboard focus is floating
  -- or elsewhere. Keep the earliest geometry for a burst, with fallback anchors
  -- when more than one window closes before the next event-loop turn.
  function self.prepare_close(window, previous)
    local workspace = window and window.workspace
    if not workspace or not workspace.monitor then return nil end
    if gesture and gesture.initial and gesture.initial.workspace_id == workspace.id then return nil end
    local s = self.snapshot(workspace.id, workspace.monitor.name)
    if not s then return nil end
    local removed
    for _, column in ipairs(s.columns) do
      for _, member in ipairs(column.windows) do
        if member.address == window.address then removed = column end
      end
    end
    if not removed then return nil end
    local offscreen = removed.finish <= s.offset + EPS or removed.start >= s.offset + s.width - EPS
    if previous and previous.workspace_id == s.workspace_id and previous.monitor_name == s.monitor_name
      and previous.generation == generation(s.workspace_id) then
      previous.excluded[window.address] = true
      previous.offscreen = previous.offscreen and offscreen
      return previous
    end
    local anchors = {}
    for _, column in ipairs(s.columns) do
      for _, member in ipairs(column.windows) do
        if member.address ~= window.address then
          anchors[#anchors+1] = {address=member.address, screen_start=column.start-s.offset,
            overlap=math.max(0, math.min(column.finish,s.offset+s.width)-math.max(column.start,s.offset))}
        end
      end
    end
    table.sort(anchors, function(a,b) return a.overlap > b.overlap end)
    return {generation=generation(s.workspace_id), workspace_id=s.workspace_id, monitor_name=s.monitor_name,
      offscreen=offscreen, anchors=anchors, excluded={[window.address]=true}}
  end

  function self.finish_close(token)
    if not token or token.generation ~= generation(token.workspace_id) then return noop() end
    local s = self.snapshot(token.workspace_id, token.monitor_name)
    if not s then return noop() end
    -- Consume the token even if there is no camera movement. A second callback
    -- must never replay an already-completed repair.
    self.invalidate_workspace(token.workspace_id)
    if token.offscreen then
      for _, anchor in ipairs(token.anchors) do
        if not token.excluded[anchor.address] then
          for _, column in ipairs(s.columns) do
            for _, member in ipairs(column.windows) do
              if member.address == anchor.address then return pan_to(s,column.start-anchor.screen_start) end
            end
          end
        end
      end
    end
    return pan_to(s, G.clamp(s,s.offset))
  end

  return self
end

return M
