-- replayer.lua — post mouse + keyboard events with pause_before timing.
-- Supports auto_path mode: drops recorded mouse_moves and interpolates the
-- cursor along a straight line between successive click positions at a
-- configurable speed (pixels/sec). Optional click circles via effects.
local eventtap = require('hs.eventtap')
local event_t  = eventtap.event
local kc       = hs.keycodes.map
local effects  = require('sdr.effects')

local M = {}

local active_timer = nil
local on_done_callback = nil
local on_progress_callback = nil

-- Snapshot SU window position at replay start; rewrite window-relative coords
-- (x_window/y_window) onto current absolute screen position.
local su_anchor = nil

-- Auto-path state set per .play() call.
local auto_path = false
local auto_path_pps = 1000
local auto_path_easing = 'in_out'
local show_click_effects = false

local function ease(t, kind)
  if kind == 'linear' then return t
  elseif kind == 'in'    then return t * t * t
  elseif kind == 'out'   then local u = 1 - t; return 1 - u * u * u
  else -- in_out
    if t < 0.5 then return 4 * t * t * t end
    local u = -2 * t + 2
    return 1 - u * u * u / 2
  end
end

-- Last cursor position posted by replayer. Used as start point for auto-path
-- interpolation to the next event location.
local last_cursor = nil

local function su_window_frame()
  local app = hs.application.find('SketchUp')
  if not app then return nil end
  local w = app:mainWindow() or app:focusedWindow() or app:allWindows()[1]
  return w and w:frame() or nil
end

local function resolved_xy(evt)
  if evt.x_window ~= nil and evt.y_window ~= nil and su_anchor then
    return su_anchor.x + evt.x_window, su_anchor.y + evt.y_window
  end
  return evt.x, evt.y
end

-- hs.eventtap.event APIs expect modifiers as an array of strings
-- (e.g. {'cmd','shift'}). We store the same format on record.
local function mods_array(mods)
  if type(mods) ~= 'table' then return {} end
  return mods
end

-- True until the next mouse_up — so we can post drag events instead of plain
-- mouseMoved when the cursor moves with a button held.
local drag_active = false

local function post_event(evt)
  if evt.type == 'mouse_down' then
    local btn = evt.button == 'right' and event_t.types.rightMouseDown
             or evt.button == 'middle' and event_t.types.otherMouseDown
             or event_t.types.leftMouseDown
    drag_active = true
    event_t.newMouseEvent(btn, { x = select(1, resolved_xy(evt)), y = select(2, resolved_xy(evt)) }, mods_array(evt.modifiers)):post()

  elseif evt.type == 'mouse_up' then
    local btn = evt.button == 'right' and event_t.types.rightMouseUp
             or evt.button == 'middle' and event_t.types.otherMouseUp
             or event_t.types.leftMouseUp
    drag_active = false
    event_t.newMouseEvent(btn, { x = select(1, resolved_xy(evt)), y = select(2, resolved_xy(evt)) }, mods_array(evt.modifiers)):post()

  elseif evt.type == 'mouse_move' then
    local mx, my = resolved_xy(evt)
    hs.mouse.absolutePosition({ x = mx, y = my })
    local mt = drag_active and event_t.types.leftMouseDragged or event_t.types.mouseMoved
    event_t.newMouseEvent(mt, { x = mx, y = my }, {}):post()

  elseif evt.type == 'key_down' then
    local mods = mods_array(evt.modifiers)
    local e = evt.keycode
      and event_t.newKeyEvent(mods, evt.keycode, true)
      or  event_t.newKeyEvent(mods, evt.key,     true)
    e:post()

  elseif evt.type == 'key_up' then
    local mods = mods_array(evt.modifiers)
    local e = evt.keycode
      and event_t.newKeyEvent(mods, evt.keycode, false)
      or  event_t.newKeyEvent(mods, evt.key,     false)
    e:post()

  elseif evt.type == 'scroll' then
    event_t.newScrollEvent({ evt.scroll_dx or 0, evt.scroll_dy or 0 }, {}, 'pixel'):post()
  end
end

-- Play sequence. Returns immediately; events fire asynchronously.
-- opts: {on_done, on_progress, lead_ms, tail_ms}
-- Pick the next click-position from index i onwards (for auto-path interp).
-- Returns x, y or nil, nil if no more clicks ahead.
local function next_click_xy(events, from_i)
  for j = from_i, #events do
    local e = events[j]
    if e.type == 'mouse_down' or e.type == 'mouse_up' then
      return resolved_xy(e)
    end
  end
  return nil, nil
end

-- Animate cursor from last_cursor to (tx, ty) over distance/auto_path_pps
-- seconds, then call on_done. ~60 fps. Easing applied via ease(t).
local function animate_to(tx, ty, on_done)
  if not last_cursor then
    hs.mouse.absolutePosition({ x = tx, y = ty })
    last_cursor = { x = tx, y = ty }
    on_done()
    return
  end
  local dx = tx - last_cursor.x
  local dy = ty - last_cursor.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1.5 then
    on_done()
    return
  end
  local duration = dist / math.max(50, auto_path_pps)
  local steps = math.max(2, math.floor(duration * 60 + 0.5))
  local step_dur = duration / steps
  local sx, sy = last_cursor.x, last_cursor.y
  local k = 0
  local function step()
    k = k + 1
    local t = ease(k / steps, auto_path_easing)
    local x = sx + dx * t
    local y = sy + dy * t
    hs.mouse.absolutePosition({ x = x, y = y })
    event_t.newMouseEvent(event_t.types.mouseMoved, { x = x, y = y }, {}):post()
    if k < steps then
      hs.timer.doAfter(step_dur, step)
    else
      last_cursor = { x = tx, y = ty }
      on_done()
    end
  end
  hs.timer.doAfter(step_dur, step)
end

function M.play(sequence, opts)
  if active_timer then return false, 'replay already in progress' end
  opts = opts or {}
  on_done_callback     = opts.on_done
  on_progress_callback = opts.on_progress

  su_anchor = su_window_frame()
  drag_active = false
  last_cursor = nil

  local pb = (sequence.playback or {})
  auto_path = pb.auto_path == true
  auto_path_pps = tonumber(pb.auto_path_pps) or 1000
  auto_path_easing = pb.auto_path_easing or 'in_out'
  show_click_effects = pb.show_click_effects == true

  -- When auto_path, drop recorded mouse_move events; we'll interpolate.
  local events = sequence.events
  if auto_path then
    local filtered = {}
    for _, e in ipairs(events) do
      if e.type ~= 'mouse_move' then table.insert(filtered, e) end
    end
    events = filtered
  end

  local lead = opts.lead_ms or 0
  local tail = opts.tail_ms or 0
  local i = 1

  local function trigger_click_effect(evt)
    if not show_click_effects then return end
    if evt.type == 'mouse_down' then
      local x, y = resolved_xy(evt)
      effects.click_dot(x, y)
    end
  end

  local fire_next
  fire_next = function()
    if i > #events then
      hs.timer.doAfter(tail / 1000, function()
        active_timer = nil
        if on_done_callback then on_done_callback() end
      end)
      return
    end
    local evt = events[i]
    local pause = math.max(0, evt.pause_before_ms or 0)

    local function do_event()
      post_event(evt)
      if evt.type == 'mouse_down' or evt.type == 'mouse_up' or evt.type == 'mouse_move' then
        last_cursor = { x = select(1, resolved_xy(evt)), y = select(2, resolved_xy(evt)) }
      end
      trigger_click_effect(evt)
      if on_progress_callback then on_progress_callback(i, #events, evt) end
      i = i + 1
      fire_next()
    end

    hs.timer.doAfter(pause / 1000, function()
      if auto_path and (evt.type == 'mouse_down' or evt.type == 'mouse_up') then
        local tx, ty = resolved_xy(evt)
        animate_to(tx, ty, do_event)
      else
        do_event()
      end
    end)
  end

  active_timer = true
  hs.timer.doAfter(lead / 1000, fire_next)
  return true
end

function M.is_playing()
  return active_timer ~= nil
end

function M.stop()
  active_timer = nil
end

function M.total_duration_ms(sequence, lead_ms, tail_ms)
  local total = (lead_ms or 0) + (tail_ms or 0)
  local pb = sequence.playback or {}
  local ap  = pb.auto_path == true
  local pps = tonumber(pb.auto_path_pps) or 1000
  local prev_xy = nil
  for _, e in ipairs(sequence.events) do
    if ap and e.type == 'mouse_move' then
      -- skipped in playback
    else
      total = total + math.max(0, e.pause_before_ms or 0)
      if ap and (e.type == 'mouse_down' or e.type == 'mouse_up') then
        local x = e.x_window and (e.x_window) or e.x
        local y = e.y_window and (e.y_window) or e.y
        if prev_xy and x and y then
          local dx = x - prev_xy.x
          local dy = y - prev_xy.y
          local dist = math.sqrt(dx * dx + dy * dy)
          total = total + (dist / math.max(50, pps)) * 1000
        end
        if x and y then prev_xy = { x = x, y = y } end
      end
    end
  end
  return total
end

return M
