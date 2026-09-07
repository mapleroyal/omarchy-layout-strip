-- Declare the versioned native bridge through Hyprland's plugin config API.
local M = {}

function M.load(base)
  base = base or ((os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")) .. "/hypr-tape")
  local function unavailable(reason)
    hl.notification.create({
      text = "Tape browsing: " .. reason .. ". Using fallback controls. Run hypr-tape-rebuild after updating/restarting Hyprland.",
      duration = 8000,
      icon = "warning",
    })
    return { available = false, reason = reason }
  end

  local ok, build = pcall(dofile, base .. "/active.lua")
  if not ok or type(build) ~= "table" or type(build.path) ~= "string" or
     type(build.version) ~= "string" or type(build.git_hash) ~= "string" then
    return unavailable("native bridge is missing or its build manifest is invalid")
  end
  if build.version ~= hl.version() then
    return unavailable("native bridge was built for Hyprland " .. build.version .. ", running " .. hl.version())
  end
  if build.path:sub(1, 1) ~= "/" then
    return unavailable("native bridge path must be absolute")
  end
  local file = io.open(build.path, "rb")
  if not file then return unavailable("native bridge library is missing") end
  file:close()

  -- Loading is deferred until parsing finishes. Consumers resolve
  -- hl.plugin.tape when called, rather than capturing it during config parsing.
  -- Hyprland itself reports a native notification for an ABI/load failure.
  hl.plugin.load(build.path)
  return { declared = true, path = build.path, version = build.version, git_hash = build.git_hash }
end

return M
