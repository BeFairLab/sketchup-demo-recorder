-- replayer.lua — post mouse + keyboard events with pause_before timing.
local eventtap = require('hs.eventtap')
local event_t  = eventtap.event
local kc       = hs.keycodes.map

local M = {}

local active_timer = nil
local on_done_callback = nil
local on_progress_callback = nil

local function flags_from_modifiers(mods)
  local out = {}
  for _, m in ipairs(mods or {}) do out[m] = true end
  return out
end

local function post_event(evt)
  if evt.type == 'mouse_down' then
    local btn = evt.button == 'right' and event_t.types.rightMouseDown
             or evt.button == 'middle' and event_t.types.otherMouseDown
             or event_t.types.leftMouseDown
    event_t.newMouseEvent(btn, { x = evt.x, y = evt.y }, flags_from_modifiers(evt.modifiers)):post()

  elseif evt.type == 'mouse_up' then
    local btn = evt.button == 'right' and event_t.types.rightMouseUp
             or evt.button == 'middle' and event_t.types.otherMouseUp
             or event_t.types.leftMouseUp
    event_t.newMouseEvent(btn, { x = evt.x, y = evt.y }, flags_from_modifiers(evt.modifiers)):post()

  elseif evt.type == 'mouse_move' then
    -- Use mouseMoved + position.
    hs.mouse.absolutePosition({ x = evt.x, y = evt.y })

  elseif evt.type == 'key_down' then
    local key = evt.key
    local mods = evt.modifiers or {}
    -- newKeyEvent expects a key NAME (string) or keycode. We stored both.
    -- Prefer keycode if present, else key.
    local e
    if evt.keycode then
      e = event_t.newKeyEvent(mods, evt.keycode, true)
    else
      e = event_t.newKeyEvent(mods, key, true)
    end
    e:post()

  elseif evt.type == 'key_up' then
    local e
    if evt.keycode then
      e = event_t.newKeyEvent(evt.modifiers or {}, evt.keycode, false)
    else
      e = event_t.newKeyEvent(evt.modifiers or {}, evt.key, false)
    end
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
