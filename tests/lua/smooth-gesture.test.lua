-- Exercise gesture policy through a mocked native camera. Its direct and
-- animated paths share geometry but are logged separately to catch accidentally
-- bypassing animations for keyboard moves, release snaps, or cancellation.
local base = arg[1] or "backend/"
local Tape = dofile(base .. "tape.lua")

local function near(actual, expected, message)
  assert(math.abs(actual - expected) < 0.001,
    (message or "unexpected camera position") .. ": " .. tostring(actual) .. " != " .. tostring(expected))
end

local function fixture(widths, options)
  options = options or {}
  local c = { offset = options.offset or 0, rendered_offset = options.rendered_offset,
    width = options.width or 1000,
    calls = {}, commands = {}, windows = {}, inhibited = false }
  c.monitor = { id = 0, name = "test-output" }
  c.workspace = { id = 1, name = "1", tiled_layout = "scrolling", monitor = c.monitor }
  c.monitor.active_workspace = c.workspace
  c.current = c.workspace
  for index, width in ipairs(widths) do
    local window = { address = string.format("0x%x", index), mapped = true,
      hidden = false, floating = false, fullscreen = 0, workspace = c.workspace }
    window.layout = { name = "scrolling", column = { index = index - 1,
      width = width, windows = { window } } }
    c.windows[index] = window
  end
  c.active = c.windows[options.active or 1]

  local native = {}
  function native.snapshot()
    if c.current ~= c.workspace then return { ok = false } end
    return { ok = true, width = c.width, offset = c.offset, renderedOffset = c.rendered_offset }
  end
  local function pan(kind, delta, exact, workspace_id, monitor_name)
    c.calls[#c.calls + 1] = { kind = kind, delta = delta, exact = exact,
      workspace_id = workspace_id, monitor_name = monitor_name }
    if c.pan_error then return { ok = false, error = "test camera rejected movement" } end
    c.offset = c.offset - delta
    if kind == "direct" and c.rendered_offset ~= nil then c.rendered_offset = c.offset end
    return { ok = true }
  end
  function native.pan(...) return pan("animated", ...) end
  if options.direct ~= false then
    function native.pan_direct(...) return pan("direct", ...) end
  end

  local hl = { plugin = { tape = native }, dsp = {} }
  function hl.get_active_workspace() return c.current end
  function hl.get_active_special_workspace() return nil end
  function hl.get_active_window() return c.active end
  function hl.get_workspace_windows(workspace)
    return workspace == c.workspace and c.windows or {}
  end
  function hl.get_monitors() return { c.monitor } end
  function hl.get_config() return options.fullscreen_on_one ~= false end
  function hl.dsp.layout(command) return { command = command } end
  function hl.dsp.focus(args) return { focus = args.window, direction = args.direction } end
  function hl.dispatch(action)
    c.commands[#c.commands + 1] = action
    if action.command == "inhibit_scroll 1" then c.inhibited = true end
    if action.command == "inhibit_scroll 0" then c.inhibited = false end
    if action.command and action.command:match("^colresize ") then
      c.active.layout.column.width = tonumber(action.command:match("^colresize (.+)$"))
    end
    if action.focus then
      assert(c.inhibited, "gesture landing focus must not move the native camera")
      c.active = action.focus
    end
    return { ok = true }
  end
  c.hl, c.native, c.tape = hl, native, Tape.new(hl)
  function c.update(displacement, extra)
    local event = extra or {}
    event.delta = { x = -displacement, y = 0 }
    return c.tape.smooth_update(event)
  end
  return c
end

local function last_kind(c, expected)
  assert(#c.calls > 0 and c.calls[#c.calls].kind == expected,
    "expected " .. expected .. " camera movement")
end

-- Fingers move the camera without changing focus; lifting them retains the
-- established column landing and focus rules, with animation restored.
local c = fixture({ .5, .5, .5, .5 })
c.tape.smooth_begin({})
assert(c.update(120).changed)
assert(c.update(80).changed)
near(c.offset, 200)
assert(#c.calls == 2 and c.calls[1].kind == "direct" and c.calls[2].kind == "direct")
assert(c.active == c.windows[1] and #c.commands == 0, "drag must leave keyboard focus alone")
assert(c.tape.smooth_end({ cancelled = false }).ok)
near(c.offset, 500)
last_kind(c, "animated")
assert(c.active == c.windows[3], "rightward landing selects the last fully visible column")
assert(c.commands[1].command == "inhibit_scroll 1" and c.commands[3].command == "inhibit_scroll 0")
assert(not c.inhibited, "focus inhibition must end synchronously")

-- Regrabbing an unfinished landing holds the actual on-screen position. The
-- next finger movement starts there, while cancellation keeps the old goal.
c = fixture({ 1, 1, 1, 1 }, { offset = 1000, rendered_offset = 200, active = 2 })
assert(c.tape.smooth_begin({}).ok)
near(c.offset, 200, "gesture start must adopt the rendered camera")
near(c.rendered_offset, 200, "interrupting a landing must not jump the visible tape")
last_kind(c, "direct")
assert(#c.commands == 0 and c.active == c.windows[2])
c.update(10)
near(c.offset, 210, "first movement must follow the rendered origin")
near(c.rendered_offset, 210)
c.tape.smooth_end({ cancelled = true })
near(c.offset, 1000, "cancellation restores the original logical landing")
near(c.rendered_offset, 210, "cancellation must animate from the current visible position")
last_kind(c, "animated")
assert(c.active == c.windows[2])

-- The unfinished animation's distance must not count as finger travel. Ten
-- units near the intended landing cannot become a full backwards column step.
c = fixture({ 1, 1, 1, 1 }, { offset = 1000, rendered_offset = 800, active = 2 })
c.tape.smooth_begin({})
c.update(10)
c.tape.smooth_end({})
near(c.offset, 1000, "pending animation distance must not trigger a short swipe")
last_kind(c, "animated")

-- Backtracking is measured from the rendered origin too: an 80-unit net swipe
-- with deliberate reversal returns to the original resting view.
c = fixture({ 1, 1, 1, 1 }, { offset = 1000, rendered_offset = 800, active = 2 })
c.tape.smooth_begin({})
c.update(100)
c.update(-20)
c.tape.smooth_end({})
near(c.offset, 1000, "regrab backtracking must disable short-swipe advancement")
last_kind(c, "animated")

-- Rapidly grabbing and releasing with no travel continues the original
-- landing; the temporary visible camera does not become a new resting stop.
c = fixture({ 1, 1, 1 }, { offset = 1000, rendered_offset = 800, active = 2 })
c.tape.smooth_begin({})
c.tape.smooth_end({})
near(c.offset, 1000)
last_kind(c, "animated")

-- An on-screen gutter can be outside the ordinary camera bounds during a
-- landing. Adopting it must retain exact placement and avoid a clamp jump.
c = fixture({ .5, .5, .5 }, { offset = 0, rendered_offset = -200 })
c.tape.smooth_begin({})
near(c.offset, -200)
assert(c.calls[#c.calls].exact)
c.update(-10)
near(c.offset, -200, "blocked movement must preserve the visible origin")
c.update(10)
near(c.offset, -190, "movement back inside must start at the visible origin")
assert(c.calls[#c.calls].exact)
c.tape.smooth_end({ cancelled = true })
near(c.offset, 0)
last_kind(c, "animated")

-- A bridge exposing a rendered offset but lacking the direct operation keeps
-- the old behavior; beginning a gesture must not issue an animated reposition.
c = fixture({ 1, 1, 1 }, { offset = 1000, rendered_offset = 800, direct = false })
c.tape.smooth_begin({})
near(c.offset, 1000)
assert(#c.calls == 0)
c.update(10)
near(c.offset, 1010)
last_kind(c, "animated")

-- Discrete browsing and keyboard focus movement still use animated panning.
c = fixture({ .5, .5, .5, .5 })
assert(c.tape.browse("r", false).ok)
near(c.offset, 500)
last_kind(c, "animated")
assert(c.tape.focus("l", false).ok)
assert(c.tape.focus("l", false).ok)
near(c.offset, 0)
for _, call in ipairs(c.calls) do assert(call.kind == "animated") end

-- Release speed cannot fling past the view reached by the fingers.
c = fixture({ 1, 1, 1, 1 })
c.tape.smooth_begin({})
c.update(600, { velocity = { x = -1000000, y = 0 }, time = 1 })
c.tape.smooth_end({ velocity = { x = -1000000, y = 0 }, time = 2 })
near(c.offset, 1000, "fast release must land by position")
last_kind(c, "animated")

-- Long travel can cross several columns; a short monotonic swipe advances one.
c = fixture({ 1, 1, 1, 1 })
c.tape.smooth_begin({})
c.update(2200)
c.tape.smooth_end({})
near(c.offset, 2000)
c = fixture({ 1, 1, 1 })
c.tape.smooth_begin({})
c.update(80)
c.tape.smooth_end({})
near(c.offset, 1000)

-- Deliberate backtracking removes the short-swipe convenience, even when net
-- travel still reaches its threshold. A tiny swipe also returns to the start.
c = fixture({ 1, 1, 1 })
c.tape.smooth_begin({})
c.update(100)
c.update(-20)
c.tape.smooth_end({})
near(c.offset, 0, "backtracking must allow returning to the original view")
last_kind(c, "animated")
c = fixture({ 1, 1, 1 })
c.tape.smooth_begin({})
c.update(40)
c.tape.smooth_end({})
near(c.offset, 0)

-- Both sides of mixed-width columns remain resting views, so a partial column
-- can be exposed rather than always aligning the next column's left edge.
c = fixture({ .5, .667, 1 }, { width = 1200 })
c.tape.smooth_begin({})
c.update(210)
c.tape.smooth_end({})
near(c.offset, 200.4, "mixed-width landing must preserve the right-edge stop")
c.tape.smooth_begin({})
c.update(390)
c.tape.smooth_end({})
near(c.offset, 600, "mixed-width landing must preserve the left-edge stop")

-- A deliberate near-full-width peek is one resting view. Tiny movement must
-- not snap away the original within-range placement.
c = fixture({ .5, .98, .5 }, { offset = 480, active = 2 })
c.tape.smooth_begin({})
c.update(10)
c.tape.smooth_end({})
near(c.offset, 480)

-- Cancellation restores the starting camera and starting focus, using an
-- animated return even if some other event changed focus during the gesture.
c = fixture({ .5, .5, .5, .5 }, { offset = 500, active = 3 })
c.tape.smooth_begin({})
c.update(200)
c.active = c.windows[4]
c.tape.smooth_end({ cancelled = true })
near(c.offset, 500)
last_kind(c, "animated")
assert(c.active == c.windows[3] and not c.inhibited)

-- Endpoint rejection is a complete no-op. Backtracking from an edge has no
-- accumulated overscroll debt to work off before the tape follows the fingers.
c = fixture({ .5, .5, .5 })
c.tape.smooth_begin({})
assert(not c.update(-400).changed)
assert(not c.tape.smooth_end({}).changed)
assert(#c.calls == 0 and #c.commands == 0 and c.active == c.windows[1])
c.tape.smooth_begin({})
c.update(-400)
c.update(100)
near(c.offset, 100)
last_kind(c, "direct")
c.update(5000)
near(c.offset, 500, "right endpoint must clamp")
c.update(-50)
near(c.offset, 450, "reversing at the right endpoint must respond immediately")

-- An explicit half placement can legitimately leave a gutter. Smooth panning
-- into or out of it retains exact-camera permission and cancellation restores it.
c = fixture({ .3, .5, .5 }, { active = 2 })
assert(c.tape.place_half("r").ok)
near(c.offset, -200)
last_kind(c, "animated")
assert(c.calls[#c.calls].exact)
c.tape.smooth_begin({})
local count = #c.calls
assert(not c.update(-50).changed)
near(c.offset, -200)
assert(#c.calls == count, "blocked drag must preserve the intentional gutter")
c.update(100)
near(c.offset, -100)
last_kind(c, "direct")
assert(c.calls[#c.calls].exact, "direct motion outside normal bounds needs exact placement")
c.tape.smooth_end({ cancelled = true })
near(c.offset, -200)
last_kind(c, "animated")
assert(c.calls[#c.calls].exact)
c.tape.smooth_begin({})
c.update(-100)
c.tape.smooth_end({})
near(c.offset, -200)

-- A short tape, including a deliberate gutter, has no browseable neighboring
-- view. Finger motion must not normalize that placement or change focus.
c = fixture({ .3, .5 }, { active = 2, fullscreen_on_one = false })
c.tape.place_half("r")
near(c.offset, -200)
count = #c.calls
c.tape.smooth_begin({})
assert(not c.update(400).changed)
assert(not c.tape.smooth_end({}).changed)
near(c.offset, -200)
assert(#c.calls == count and c.active == c.windows[2])

-- A workspace, viewport, column width, or membership change invalidates the
-- gesture rather than applying stale geometry or restoring stale focus.
for _, mutate in ipairs({
  function(s) s.current = { id = 2, tiled_layout = "scrolling", monitor = s.monitor } end,
  function(s) s.width = s.width + 200 end,
  function(s) s.windows[2].layout.column.width = .667 end,
  function(s)
    local old = s.windows[2]
    local replacement = { address = "0xff", mapped = true, hidden = false, floating = false,
      fullscreen = 0, workspace = s.workspace }
    replacement.layout = { name = "scrolling", column = { index = old.layout.column.index,
      width = old.layout.column.width, windows = { replacement } } }
    s.windows[2] = replacement
  end,
}) do
  c = fixture({ .5, .5, .5, .5 })
  c.tape.smooth_begin({})
  c.update(100)
  mutate(c)
  count = #c.calls
  assert(not c.update(100).changed)
  assert(not c.tape.smooth_end({ cancelled = true }).changed)
  assert(#c.calls == count and #c.commands == 0, "invalidated gesture must do no further work")
end

-- Geometry may change only after the final update; release must also recheck.
c = fixture({ .5, .5, .5 })
c.tape.smooth_begin({})
c.update(100)
c.windows[2].layout.column.width = 1
count = #c.calls
assert(not c.tape.smooth_end({}).changed and #c.calls == count)

-- Old bridges remain usable: absence of the additive direct operation falls
-- back to ordinary panning without changing gesture policy.
c = fixture({ .5, .5, .5 }, { direct = false })
c.tape.smooth_begin({})
assert(c.update(100).ok)
near(c.offset, 100)
last_kind(c, "animated")
c.tape.smooth_end({})
near(c.offset, 500)

-- A rejected direct update reports the error; it must not silently make a
-- second movement through the animated operation.
c = fixture({ .5, .5, .5 })
c.tape.smooth_begin({})
c.pan_error = true
assert(c.update(100).ok == false)
assert(#c.calls == 1 and c.calls[1].kind == "direct")
near(c.offset, 0)

-- If the bridge is unavailable, cancelled fallback gestures remain no-ops and
-- a completed fallback swipe uses native directional focus just once.
c = fixture({ .5, .5, .5 })
c.hl.plugin = {}
c.tape.smooth_begin({})
c.update(100)
c.tape.smooth_end({ cancelled = true })
assert(#c.calls == 0 and #c.commands == 0)
c.tape.smooth_begin({})
c.update(100)
c.tape.smooth_end({})
assert(#c.commands == 1 and c.commands[1].direction == "r")

print("Smooth gesture tracking/regrab, animated landing/steps, focus, snap policy, backtracking, cancellation, gutters, edges, stale geometry and bridge compatibility passed")
