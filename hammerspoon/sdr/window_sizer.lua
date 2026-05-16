-- window_sizer.lua — apply viewport sizing in two modes.
--
-- mode='viewport': call companion → Sketchup.resize_viewport(w,h) →
--                  read back hs.window frame to compute screen region of model area
-- mode='window':   resize SU window itself via hs.window:setFrame
local bridge = require('sdr.companion_bridge')

local M = {}

local function find_su_window()
  local app = hs.application.find('SketchUp')
  if not app then return nil end
  return app:mainWindow() or app:focusedWindow() or app:allWindows()[1]
end

-- Returns the final recording region: {x, y, w, h} in screen points.
-- Pass viewport block from sequence: { mode, width, height, region }
function M.apply(viewport, chrome_offsets)
  chrome_offsets = chrome_offsets or { top = 70, bottom = 25, left = 0, right = 0 }

  local win = find_su_window()
  if not win then return nil, 'SketchUp window not found' end
  win:focus()

  if viewport.mode == 'viewport' then
    local _, err = bridge.resize_viewport(viewport.width, viewport.height)
    if err then return nil, 'companion: ' .. err end
    -- After resize, read SU window frame from hs.window.
    hs.timer.usleep(100000) -- 100ms for SU to settle
    local frame = win:frame()
    local region = {
      x = frame.x + chrome_offsets.left,
      y = frame.y + chrome_offsets.top,
      w = frame.w - chrome_offsets.left - chrome_offsets.right,
      h = frame.h - chrome_offsets.top - chrome_offsets.bottom,
    }
    return region

  elseif viewport.mode == 'window' then
    -- Set entire window to W×H. Keep current top-left position.
    local cur = win:frame()
    win:setFrame({ x = cur.x, y = cur.y, w = viewport.width, h = viewport.height })
    hs.timer.usleep(100000)
    local frame = win:frame()
    return { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  end

  return nil, 'unknown viewport mode: ' .. tostring(viewport.mode)
end

-- Show a translucent overlay showing the recording region. Returns the canvas.
function M.show_overlay(region)
  if not region then return nil end
  local c = hs.canvas.new(region)
  c:appendElements({
    type = 'rectangle',
    action = 'stroke',
    strokeColor = { red = 1, green = 0.2, blue = 0.2, alpha = 0.85 },
    strokeWidth = 4,
  }, {
    type = 'text',
    text = string.format('Recording region  %d×%d', region.w, region.h),
    textColor = { red = 1, green = 1, blue = 1, alpha = 1 },
    textFont  = 'Menlo',
    textSize  = 14,
    frame = { x = 8, y = 8, w = 300, h = 22 },
  })
  c:show()
  return c
end

return M
