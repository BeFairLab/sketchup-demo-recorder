-- effects.lua — visual click effects rendered as hs.canvas overlays.
-- These canvases are independent of the recording overlay → they ARE included
-- in the captured mp4 (good — shows interaction in the demo).
local M = {}

local DOT_FRAMES = 14         -- ~230ms at ~16ms/frame
local DOT_INTERVAL_MS = 16
local DOT_MAX_RADIUS = 32     -- in logical points
local DOT_INITIAL_RADIUS = 6

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
  local canvas = hs.canvas.new({
    x = x - DOT_INITIAL_RADIUS,
    y = y - DOT_INITIAL_RADIUS,
    w = DOT_INITIAL_RADIUS * 2,
    h = DOT_INITIAL_RADIUS * 2,
  })
  canvas:level('overlay')
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
end

return M
