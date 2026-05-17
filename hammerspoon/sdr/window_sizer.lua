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
    hs.timer.usleep(150000)
    local frame = win:frame()
    local scale = backing_scale(frame)

    -- SU's view.vpwidth/vpheight are LOGICAL POINTS even though resize_viewport
    -- takes pixels — do NOT divide by scale.
    local vp_pt_w = (result and result.viewport and result.viewport.w) or (viewport.width  / scale)
    local vp_pt_h = (result and result.viewport and result.viewport.h) or (viewport.height / scale)

    -- Center the window on its screen so replay reproduces consistent
    -- positions even if user manually moves SU between sessions.
    local screen = win:screen() or hs.screen.primaryScreen()
    local sf = screen:frame()
    win:setTopLeft({
      x = math.floor(sf.x + (sf.w - frame.w) / 2 + 0.5),
      y = math.floor(sf.y + (sf.h - frame.h) / 2 + 0.5),
    })
    hs.timer.usleep(100000)
    frame = win:frame()

    -- Region = viewport rect anchored to bottom-of-window minus status bar.
    -- Apply overlay_shift so capture region tracks the same nudge as the
    -- preview overlay (they're locked together).
    local shift = viewport.overlay_shift or { dx = 0, dy = 0 }
    local region = {
      x = frame.x + (shift.dx or 0),
      y = frame.y + frame.h - STATUS_BAR_PT - vp_pt_h + (shift.dy or 0),
      w = vp_pt_w,
      h = vp_pt_h,
    }
    return region, nil, { x = frame.x, y = frame.y, w = frame.w, h = frame.h }

  elseif viewport.mode == 'window' then
    -- viewport.width/height are PIXEL targets (so the captured mp4 hits that
    -- exact resolution on Retina). hs.window:setFrame takes LOGICAL POINTS.
    local screen = win:screen() or hs.screen.primaryScreen()
    local sf = screen:frame()
    local scale = backing_scale(sf)
    local w_pt = viewport.width  / scale
    local h_pt = viewport.height / scale
    win:setFrame({
      x = math.floor(sf.x + (sf.w - w_pt) / 2 + 0.5),
      y = math.floor(sf.y + (sf.h - h_pt) / 2 + 0.5),
      w = w_pt, h = h_pt,
    })
    hs.timer.usleep(100000)
    local frame = win:frame()
    return { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
           nil,
           { x = frame.x, y = frame.y, w = frame.w, h = frame.h }
  end

  return nil, 'unknown viewport mode: ' .. tostring(viewport.mode)
end

-- Overlay state. Tracks SU window and follows its moves/resizes.
local overlay_canvas = nil
local overlay_offset = nil   -- {dx, dy, w, h} relative to SU window
local overlay_filter = nil
local overlay_safe_frames = nil  -- {{name,w,h,color}, ...} centered inside region

local function frames_equal(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function rebuild_overlay_elements()
  if not overlay_canvas or not overlay_offset then return end
  overlay_canvas:replaceElements({
    type = 'rectangle',
    action = 'stroke',
    strokeColor = { red = 1, green = 0.2, blue = 0.2, alpha = 0.85 },
    strokeWidth = 3,
  }, {
    type = 'text',
    text = string.format('Recording  %d×%d', overlay_offset.w, overlay_offset.h),
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.9 },
    textFont  = 'Menlo',
    textSize  = 13,
    frame = { x = 6, y = 4, w = 240, h = 18 },
  })
  if overlay_safe_frames then
    for _, sf in ipairs(overlay_safe_frames) do
      -- centered inside the outer recording region
      local fx = (overlay_offset.w - sf.w) / 2
      local fy = (overlay_offset.h - sf.h) / 2
      overlay_canvas:appendElements({
        type = 'rectangle',
        action = 'fill',
        fillColor = { red = sf.color[1], green = sf.color[2], blue = sf.color[3], alpha = 0.10 },
        strokeColor = { red = sf.color[1], green = sf.color[2], blue = sf.color[3], alpha = 0.9 },
        strokeWidth = 2,
        frame = { x = fx, y = fy, w = sf.w, h = sf.h },
      }, {
        type = 'text',
        text = string.format('%s  %d×%d', sf.name, sf.w, sf.h),
        textColor = { red = sf.color[1], green = sf.color[2], blue = sf.color[3], alpha = 0.95 },
        textFont  = 'Menlo',
        textSize  = 12,
        frame = { x = fx + 6, y = fy + 4, w = 220, h = 16 },
      })
    end
  end
end

local function reposition_overlay()
  if not overlay_canvas or not overlay_offset then return end
  local win = find_su_window()
  if not win then return end
  local f = win:frame()
  overlay_canvas:frame({
    x = f.x + overlay_offset.dx,
    y = f.y + overlay_offset.dy,
    w = overlay_offset.w,
    h = overlay_offset.h,
  })
end

local function attach_window_follower()
  if overlay_filter then return end
  overlay_filter = hs.window.filter.new('SketchUp')
    :subscribe({ hs.window.filter.windowMoved, hs.window.filter.windowResized },
               function() reposition_overlay() end)
end

local function detach_window_follower()
  if overlay_filter then
    overlay_filter:unsubscribeAll()
    overlay_filter = nil
  end
end

-- Show overlay anchored to SU window using region absolute coords.
-- safe_frames: optional list of {name, w, h, color={r,g,b}} drawn centered.
-- shift: optional {dx, dy} extra offset applied to the overlay position only
-- (not to the recording region itself — purely for visual alignment).
function M.show_overlay(region, safe_frames, shift)
  if not region then return nil end
  M.hide_overlay()
  shift = shift or { dx = 0, dy = 0 }

  local win = find_su_window()
  if win then
    local f = win:frame()
    overlay_offset = {
      dx = region.x - f.x + (shift.dx or 0),
      dy = region.y - f.y + (shift.dy or 0),
      w  = region.w,
      h  = region.h,
    }
  else
    overlay_offset = { dx = shift.dx or 0, dy = shift.dy or 0, w = region.w, h = region.h }
  end
  overlay_safe_frames = safe_frames

  overlay_canvas = hs.canvas.new({
    x = region.x + (shift.dx or 0),
    y = region.y + (shift.dy or 0),
    w = region.w, h = region.h,
  })
  rebuild_overlay_elements()
  overlay_canvas:show()
  attach_window_follower()
  return overlay_canvas
end

function M.hide_overlay()
  if overlay_canvas then overlay_canvas:delete(); overlay_canvas = nil end
  overlay_offset = nil
  overlay_safe_frames = nil
  detach_window_follower()
end

function M.overlay_visible()
  return overlay_canvas ~= nil
end

-- Temporarily hide overlay (for screen capture). Restore via show_overlay_resume.
local saved_overlay_state = nil
function M.suppress_overlay()
  if overlay_canvas then
    saved_overlay_state = { offset = overlay_offset, safe_frames = overlay_safe_frames }
    M.hide_overlay()
  else
    saved_overlay_state = nil
  end
end

function M.resume_overlay()
  if not saved_overlay_state then return end
  local win = find_su_window()
  local f = win and win:frame() or { x = 0, y = 0 }
  -- saved_overlay_state.offset already includes any shift, so passing
  -- shift={0,0} preserves the same on-screen position.
  local region = {
    x = f.x + saved_overlay_state.offset.dx,
    y = f.y + saved_overlay_state.offset.dy,
    w = saved_overlay_state.offset.w,
    h = saved_overlay_state.offset.h,
  }
  M.show_overlay(region, saved_overlay_state.safe_frames, { dx = 0, dy = 0 })
  saved_overlay_state = nil
end

return M
