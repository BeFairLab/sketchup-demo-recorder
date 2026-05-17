-- effects.lua — visual click effects rendered as hs.canvas overlays.
-- These canvases are independent of the recording overlay → they ARE included
-- in the captured mp4 (good — shows interaction in the demo).
local M = {}

local DOT_FRAMES = 22         -- ~350ms at ~16ms/frame
local DOT_INTERVAL_MS = 16
local DOT_MAX_RADIUS = 60     -- in logical points (much more visible)
local DOT_INITIAL_RADIUS = 10

local active_dots = {}        -- {canvas, frame_idx, x, y, color}

local function tick_dot(state)
  state.frame_idx = state.frame_idx + 1
  if state.frame_idx > DOT_FRAMES then
    if state.canvas then state.canvas:delete() end
    state.canvas = nil
    return
  end
  local t = state.frame_idx / DOT_FRAMES
  local radius = DOT_INITIAL_RADIUS + (DOT_MAX_RADIUS - DOT_INITIAL_RADIUS) * t
  local alpha  = 0.85 * (1 - t)

  state.canvas:replaceElements({
    type = 'circle',
    action = 'strokeAndFill',
    center = { x = radius, y = radius },
    radius = radius,
    fillColor   = { red = state.color[1], green = state.color[2], blue = state.color[3], alpha = alpha * 0.35 },
    strokeColor = { red = state.color[1], green = state.color[2], blue = state.color[3], alpha = alpha },
    strokeWidth = 2,
  })
  state.canvas:frame({
    x = state.x - radius,
    y = state.y - radius,
    w = radius * 2,
    h = radius * 2,
  })
  hs.timer.doAfter(DOT_INTERVAL_MS / 1000, function() tick_dot(state) end)
end

-- Show an expanding fading ring at (x, y) screen coords (logical points).
-- color = {r, g, b} 0..1 (default red).
function M.click_dot(x, y, color)
  color = color or { 1.0, 0.30, 0.30 }
  hs.printf('click_dot @ %.0f,%.0f', x, y)
  local canvas = hs.canvas.new({
    x = x - DOT_INITIAL_RADIUS,
    y = y - DOT_INITIAL_RADIUS,
    w = DOT_INITIAL_RADIUS * 2,
    h = DOT_INITIAL_RADIUS * 2,
  })
  -- 'floating' is captured by screencapture; 'screenSaver' often is filtered.
  canvas:level(hs.canvas.windowLevels.floating)
  canvas:behavior({ 'canJoinAllSpaces', 'stationary' })
  canvas:appendElements({
    type = 'circle',
    action = 'strokeAndFill',
    center = { x = DOT_INITIAL_RADIUS, y = DOT_INITIAL_RADIUS },
    radius = DOT_INITIAL_RADIUS,
    fillColor   = { red = color[1], green = color[2], blue = color[3], alpha = 0.35 },
    strokeColor = { red = color[1], green = color[2], blue = color[3], alpha = 0.85 },
    strokeWidth = 2,
  })
  canvas:show()
  local state = { canvas = canvas, frame_idx = 0, x = x, y = y, color = color }
  table.insert(active_dots, state)
  hs.timer.doAfter(DOT_INTERVAL_MS / 1000, function() tick_dot(state) end)
end

function M.clear_all()
  for _, s in ipairs(active_dots) do
    if s.canvas then s.canvas:delete() end
  end
  active_dots = {}
  M.hide_keystroke()
end

-- ─── Keystroke overlay ────────────────────────────────────────────
local ks_canvas = nil
local ks_hide_timer = nil

local KEY_PADDING = 10
local KEY_FONT_SIZE = 22
local KEY_BG = { red = 0, green = 0, blue = 0, alpha = 0.72 }
local KEY_FG = { red = 1, green = 1, blue = 1, alpha = 1 }
local KEY_RADIUS = 8
local KEY_HOLD_MS = 900

-- Show key combo at (x, y) screen coords (top-left of label). Replaces any
-- active keystroke display. Auto-fades after KEY_HOLD_MS.
function M.show_keystroke(text, x, y)
  if ks_hide_timer then ks_hide_timer:stop(); ks_hide_timer = nil end
  if ks_canvas then ks_canvas:delete(); ks_canvas = nil end
  if not text or #text == 0 then return end

  -- Rough size: KEY_FONT_SIZE * 0.6 px per char.
  local w = math.max(36, math.floor(#text * KEY_FONT_SIZE * 0.62 + KEY_PADDING * 2 + 0.5))
  local h = KEY_FONT_SIZE + KEY_PADDING * 2
  hs.printf('show_keystroke "%s" @ %.0f,%.0f', tostring(text), x, y)
  ks_canvas = hs.canvas.new({ x = x, y = y, w = w, h = h })
  ks_canvas:level(hs.canvas.windowLevels.floating)
  ks_canvas:behavior({ 'canJoinAllSpaces', 'stationary' })
  ks_canvas:appendElements({
    type = 'rectangle',
    action = 'fill',
    fillColor = KEY_BG,
    roundedRectRadii = { xRadius = KEY_RADIUS, yRadius = KEY_RADIUS },
  }, {
    type = 'text',
    text = text,
    textColor = KEY_FG,
    textFont  = 'Menlo Bold',
    textSize  = KEY_FONT_SIZE,
    textAlignment = 'center',
    frame = { x = 0, y = KEY_PADDING - 2, w = w, h = KEY_FONT_SIZE + 4 },
  })
  ks_canvas:show()
  ks_hide_timer = hs.timer.doAfter(KEY_HOLD_MS / 1000, function()
    if ks_canvas then ks_canvas:delete(); ks_canvas = nil end
    ks_hide_timer = nil
  end)
end

function M.hide_keystroke()
  if ks_hide_timer then ks_hide_timer:stop(); ks_hide_timer = nil end
  if ks_canvas then ks_canvas:delete(); ks_canvas = nil end
end

return M
