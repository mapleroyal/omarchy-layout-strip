-- The bar reads compositor-owned column metadata. Geometry is never inferred
-- from animated client positions or the order of hyprctl's client list.
local M = {}
local array = {}

local function quote(value)
  return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(character)
    if character == '"' then return '\\"' end
    if character == '\\' then return '\\\\' end
    return string.format('\\u%04x', string.byte(character))
  end) .. '"'
end

local function json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "string" then return quote(value) end
  if kind == "boolean" then return tostring(value) end
  if kind == "number" then
    return value == value and value ~= math.huge and value ~= -math.huge and tostring(value) or "null"
  end
  if kind ~= "table" then error("Unsupported bar JSON value: " .. kind) end
  local parts = {}
  if getmetatable(value) == array then
    for _, item in ipairs(value) do parts[#parts + 1] = json(item) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for key, item in pairs(value) do parts[#parts + 1] = quote(key) .. ":" .. json(item) end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.new(hl, tape, finish_navigation)
  local self = {protocol_version = 2}

  local function displayed_workspace(monitor_name)
    local workspace, monitor
    if monitor_name then
      for _, candidate in ipairs(hl.get_monitors()) do
        if candidate.name == monitor_name then
          monitor = candidate
          workspace = monitor.active_special_workspace or monitor.active_workspace
          break
        end
      end
    else
      workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
      monitor = workspace and workspace.monitor
    end
    return workspace, monitor
  end

  local function bridge()
    return hl.plugin and hl.plugin.tape
  end

  local function valid_address(address)
    return type(address) == "string" and address:match("^0x%x+$") ~= nil
  end

  -- Context belongs to the strip/menu at the time of the user's action. A
  -- workspace switch or removed window must not redirect a stale request.
  local function action_workspace(workspace_id, monitor_name)
    if type(workspace_id) ~= "number" or workspace_id % 1 ~= 0 then
      return nil, "A workspace ID is required"
    end
    if type(monitor_name) ~= "string" or monitor_name == "" then
      return nil, "A monitor name is required"
    end
    local workspace, monitor = displayed_workspace(monitor_name)
    if not monitor then return nil, "The strip's monitor is no longer available" end
    if not workspace or workspace.id ~= workspace_id then
      return nil, "The strip's workspace is no longer displayed on this monitor"
    end
    if workspace.tiled_layout ~= "scrolling" then
      return nil, "The strip's workspace no longer uses the scrolling layout"
    end
    return workspace
  end

  local function find_column_window(workspace, address)
    if not valid_address(address) then return nil, "Invalid window address" end
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      if window.address:lower() == address:lower() then
        local layout = window.layout
        local column = layout and layout.name == "scrolling" and layout.column
        if window.mapped and not window.hidden and not window.floating and column and column.index ~= nil then
          return window
        end
        return nil, "The window is no longer a visible scrolling column"
      end
    end
    return nil, "The window is no longer in this workspace"
  end

  local function action_reply(action)
    local ok, result = pcall(action)
    if not ok then return json({ ok = false, protocolVersion = 2, error = tostring(result) }) end
    if type(result) ~= "table" or type(result.ok) ~= "boolean" then
      return json({ ok = false, protocolVersion = 2, error = "The compositor returned an invalid action result" })
    end
    result.protocolVersion = 2
    return json(result)
  end

  local function snapshot_data(monitor_name, region_x, region_y, region_width, region_height)
    local workspace, monitor = displayed_workspace(monitor_name)
    local columns = setmetatable({}, array)
    local active = hl.get_active_window()
    local native = bridge()
    local info_ok, info = pcall(function() return native and native.info and native.info() end)
    local native_v2 = info_ok and type(info) == "table" and info.ok == true and info.protocolVersion == 2
    local result = {
      ok = true, protocolVersion = 2, nativeProtocolVersion = native_v2 and 2 or 0,
      capabilities = {addressedCamera=native_v2 and info.addressedCamera == true,
        ownedRegions=native_v2 and info.ownedRegions == true},
      available = tape.available(), columns = columns,
      reorderAvailable = native_v2 and info.reorder == true and type(native.reorder) == "function",
      protectRegionAvailable = native_v2 and info.ownedRegions == true and type(native.protect_bar_region) == "function",
      workspaceId = workspace and workspace.id or 0,
      workspaceName = workspace and workspace.name or "",
      monitorId = monitor and monitor.id or -1,
      monitorName = monitor and monitor.name or monitor_name or "",
      layout = workspace and workspace.tiled_layout or "",
      activeAddress = active and active.address or "",
    }
    -- Only the live widget supplies a region. Plain snapshots stay read-only;
    -- this short-lived registration prevents the compositor's mouse-release
    -- handler from fitting the old focused window before the bar action runs.
    if region_x ~= nil or region_y ~= nil or region_width ~= nil or region_height ~= nil then
      local function finite(value)
        return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
      end
      result.protectRegionRegistered = false
      if type(monitor_name) ~= "string" or monitor_name == "" then
        result.protectRegionError = "A monitor name is required for the strip input region"
      elseif not finite(region_x) or not finite(region_y) or not finite(region_width) or not finite(region_height)
        or not ((region_width > 0 and region_height > 0) or (region_width == 0 and region_height == 0)) then
        result.protectRegionError = "The strip input region requires finite coordinates and dimensions that are both positive or both zero"
      elseif result.protectRegionAvailable then
        local ok, registration = pcall(native.protect_bar_region, monitor_name, region_x, region_y, region_width, region_height)
        local accepted = ok and type(registration) == "table" and registration.ok == true
        result.protectRegionRegistered = accepted and region_width > 0
        result.protectRegionCleared = accepted and region_width == 0
        if not accepted then
          result.protectRegionError = not ok and tostring(registration)
            or type(registration) == "table" and registration.error or "The compositor rejected the strip input region"
        end
      end
    end
    if not workspace or workspace.tiled_layout ~= "scrolling" then return result end
    local by_index = {}
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      local layout = window.layout
      local column = layout and layout.name == "scrolling" and layout.column
      if window.mapped and not window.hidden and not window.floating and column and column.index ~= nil then
        local focused = active and active.address == window.address or false
        local existing = by_index[column.index]
        -- A focused stack member can stand for the column; stacking has no UI.
        if not existing or focused then
          by_index[column.index] = {
            index = column.index, address = window.address, class = window.class or "",
            title = window.title or "", width = column.width or 0.5, focused = focused,
            fullscreen = window.fullscreen ~= 0,
          }
        end
      end
    end
    for _, column in pairs(by_index) do columns[#columns + 1] = column end
    table.sort(columns, function(a, b) return a.index < b.index end)
    for _, column in ipairs(columns) do
      if column.fullscreen or (#columns == 1 and hl.get_config("scrolling.fullscreen_on_one_column")) then
        column.width = 1
      end
      column.size = column.width < (0.5 + 0.667) / 2 and "small"
        or column.width < (0.667 + 1) / 2 and "medium" or "large"
    end
    return result
  end

  function self.snapshot(monitor_name, ...)
    local ok, result = pcall(snapshot_data, monitor_name, ...)
    if not ok then result = {ok=false, protocolVersion=2, error=tostring(result), columns=setmetatable({},array)} end
    return json(result)
  end

  function self.snapshot_all(monitors)
    return action_reply(function()
      if type(monitors) ~= "table" or #monitors > 64 then return {ok=false,error="Expected at most 64 monitor names"} end
      local snapshots = setmetatable({},array)
      local seen = {}
      for _, name in ipairs(monitors) do
        if type(name) ~= "string" or name == "" or seen[name] then return {ok=false,error="Monitor names must be nonempty and unique"} end
        seen[name] = true
        snapshots[#snapshots+1] = snapshot_data(name)
      end
      return {ok=true,snapshots=snapshots}
    end)
  end

  local function protect_region(monitor_name, x, y, width, height, owner)
    local native = bridge()
    local info = native and native.info and native.info()
    if type(info) ~= "table" or info.ok ~= true or info.protocolVersion ~= 2 or info.ownedRegions ~= true
      or type(native.protect_bar_region) ~= "function" then return {ok=false,error="Native protocol v2 owned regions are unavailable"} end
    if type(owner) ~= "string" or owner == "" then return {ok=false,error="A region owner is required"} end
    local result = native.protect_bar_region(monitor_name,x,y,width,height,owner)
    if type(result) ~= "table" then return {ok=false,error="Invalid native region result"} end
    return result
  end

  function self.protect_region(monitor_name,x,y,width,height,owner)
    return action_reply(function() return protect_region(monitor_name,x,y,width,height,owner) end)
  end

  function self.protect_regions(regions,owner)
    return action_reply(function()
      if type(regions) ~= "table" or #regions > 64 then return {ok=false,error="Expected at most 64 input regions"} end
      if type(owner) ~= "string" or owner == "" then return {ok=false,error="A region owner is required"} end
      local replies = setmetatable({},array)
      local accepted = true
      for _, region in ipairs(regions) do
        if type(region) ~= "table" then return {ok=false,error="Invalid input region"} end
        local result = protect_region(region.monitor,region.x,region.y,region.width,region.height,owner)
        result.monitor = region.monitor
        replies[#replies+1] = result
        accepted = accepted and result.ok == true
      end
      return {ok=accepted,regions=replies,error=not accepted and "One or more input regions were rejected" or nil}
    end)
  end

  function self.focus(address, workspace_id, monitor_name)
    return action_reply(function() return finish_navigation(tape.jump(address, workspace_id, monitor_name)) end)
  end

  function self.reorder(address, target_address, side, workspace_id, monitor_name)
    return action_reply(function()
      if side ~= "before" and side ~= "after" then
        return { ok = false, error = "Reorder side must be before or after" }
      end
      local workspace, reason = action_workspace(workspace_id, monitor_name)
      if not workspace then return { ok = false, error = reason } end
      local source, source_error = find_column_window(workspace, address)
      if not source then return { ok = false, error = source_error } end
      local target, target_error = find_column_window(workspace, target_address)
      if not target then return { ok = false, error = target_error } end
      local native = bridge()
      if not native or type(native.reorder) ~= "function" then
        return { ok = false, error = "The native tape bridge does not support reordering" }
      end
      -- Reordering must never activate its source or target. In particular, do
      -- not use jump, swapcol, or finish_navigation's pointer refocus here.
      local info = native.info and native.info()
      if type(info) ~= "table" or info.ok ~= true or info.protocolVersion ~= 2 or info.reorder ~= true then
        return {ok=false,error="Native protocol v2 reorder is unavailable"}
      end
      local result = native.reorder(source.address, target.address, side, workspace_id, monitor_name)
      if type(result) == "table" and result.ok == true and result.changed ~= false then tape.invalidate_workspace(workspace_id) end
      return result
    end)
  end

  function self.close(address, workspace_id, monitor_name)
    return action_reply(function()
      local workspace, reason = action_workspace(workspace_id, monitor_name)
      if not workspace then return { ok = false, error = reason } end
      local window, window_error = find_column_window(workspace, address)
      if not window then return { ok = false, error = window_error } end
      -- Match four-finger swipe-down: request an ordinary client close, with
      -- existing close lifecycle geometry repair and normal app save prompts.
      return finish_navigation(hl.dispatch(hl.dsp.window.close({ window = "address:" .. window.address })))
    end)
  end

  return self
end

return M
