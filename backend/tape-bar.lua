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
  local self = {}

  function self.snapshot(monitor_name)
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
    local columns = setmetatable({}, array)
    local active = hl.get_active_window()
    local result = {
      ok = true, available = tape.available(), columns = columns,
      workspaceId = workspace and workspace.id or 0,
      workspaceName = workspace and workspace.name or "",
      monitorId = monitor and monitor.id or -1,
      monitorName = monitor and monitor.name or monitor_name or "",
      layout = workspace and workspace.tiled_layout or "",
      activeAddress = active and active.address or "",
    }
    if not workspace or workspace.tiled_layout ~= "scrolling" then return json(result) end
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
    return json(result)
  end

  function self.focus(address, workspace_id, monitor_name)
    return json(finish_navigation(tape.jump(address, workspace_id, monitor_name)))
  end

  return self
end

return M
