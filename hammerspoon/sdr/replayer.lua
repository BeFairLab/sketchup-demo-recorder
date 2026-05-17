-- replayer.lua — post mouse + keyboard events with pause_before timing.
local eventtap = require('hs.eventtap')
local event_t  = eventtap.event
local kc       = hs.keycodes.map

local M = {}

local active_timer = nil
local on_done_callback = nil
local on_progress_callback = nil

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
    event_t.newMouseEvent(btn, { x = evt.x, y = evt.y }, mods_array(evt.modifiers)):post()

  elseif evt.type == 'mouse_up' then
    local btn = evt.button == 'right' and event_t.types.rightMouseUp
             or evt.button == 'middle' and event_t.types.otherMouseUp
             or event_t.types.leftMouseUp
    drag_active = false
    event_t.newMouseEvent(btn, { x = evt.x, y = evt.y }, mods_array(evt.modifiers)):post()

  elseif evt.type == 'mouse_move' then
    -- Warp cursor AND post a synthetic motion event so SU tools react.
    hs.mouse.absolutePosition({ x = evt.x, y = evt.y })
    local mt = drag_active and event_t.types.leftMouseDragged or event_t.types.mouseMoved
    event_t.newMouseEvent(mt, { x = evt.x, y = evt.y }, {}):post()

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
function M.play(sequence, opts)
  if active_timer then return false, 'replay already in progress' end
  opts = opts or {}
  on_done_callback     = opts.on_done
  on_progress_callback = opts.on_progress

  local lead = opts.lead_ms or 0
  local tail = opts.tail_ms or 0
  local i = 1
  local cumulative_ms = lead

  local schedule
  schedule = function()
    if i > #sequence.events then
      -- Tail then fire on_done.
      hs.timer.doAfter(tail / 1000, function()
        active_timer = nil
        if on_done_callback then on_done_callback() end
      end)
      return
    end
    local evt = sequence.events[i]
    local pause = math.max(0, evt.pause_before_ms or 0)
    hs.timer.doAfter(pause / 1000, function()
      post_event(evt)
      if on_progress_callback then on_progress_callback(i, #sequence.events, evt) end
      i = i + 1
      schedule()
    end)
  end

  active_timer = true
  hs.timer.doAfter(lead / 1000, schedule)
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
  for _, e in ipairs(sequence.events) do
    total = total + math.max(0, e.pause_before_ms or 0)
  end
  return total
end

return M
