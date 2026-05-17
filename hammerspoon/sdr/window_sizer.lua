-- window_sizer.lua — apply viewport sizing in two modes.
--
-- mode='viewport': call companion → Sketchup.resize_viewport(w,h) →
--                  read back hs.window frame to compute screen region of model area.
--                  Companion reports vp size in PIXELS; we convert to logical pts.
-- mode='window':   resize SU window itself via hs.window:setFrame.
local bridge = require('sdr.companion_bridge')

local M = {}

-- Empirically: SU 2026 status bar = 25 logical pts. Title + toolbar = the rest
-- (varies). We anchor the viewport to the BOTTOM of the window minus status,
-- which avoids guessing top-chrome height.
local STATUS_BAR_PT = 25

local function find_su_window()
  local app = hs.application.find('SketchUp')
  if not app then return nil end
  return app:mainWindow() or app:focusedWindow() or app:allWindows()[1]
end

local function backing_scale(frame)
  -- Pick the screen that contains the window center.
  local cx = frame.x + frame.w / 2
  local cy = frame.y + frame.h / 2
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:frame()
    if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
      local mode = s:currentMode()
      return mode and mode.scale or 1
    end
  end
  return 1
end

-- Returns the final recording region: {x, y, w, h} in screen points.
function M.apply(viewport, chrome_offsets)
  local win = find_su_window()
  if not win then return nil, 'SketchUp window not found' end
  win:focus()

  if viewport.mode == 'viewport' then
    local result, err = bridge.resize_viewport(viewport.width, viewport.height)
    if err then return nil, 'companion: ' .. err end
    hs.timer.usleep(150000) -- 150ms for SU to settle
    local frame = win:frame()
    local scale = backing_scale(frame)

    -- Companion-reported viewport pixel size (post-resize). Trust this over
    -- the requested width/height in case SU clamped to display bounds.
    local vp_px_w = (result and result.viewport and result.viewport.w) or viewport.width
    local vp_px_h = (result and result.viewport and result.viewport.h) or viewport.height
    local vp_pt_w = vp_px_w / scale
    local vp_pt_h = vp_px_h / scale

    -- Region anchored to bottom-of-window minus status bar.
    local region = {
      x = frame.x,
      y = frame.y + frame.h - STATUS_BAR_PT - vp_pt_h,
      w = vp_pt_w,
      h = vp_pt_h,
    }
    return region

  elseif viewport.mode == 'window' then
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
