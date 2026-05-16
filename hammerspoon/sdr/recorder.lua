-- recorder.lua — capture global mouse + keyboard events into a sequence.
--
-- Events recorded:
--   * mouse_down / mouse_up (left, right, middle)
--   * mouse_move — throttled to MOUSE_MOVE_MIN_MS between samples
--   * scroll
--   * key_down / key_up — but tool hotkeys are filtered out
--
-- All coordinates are absolute screen points (not window-relative). At replay
-- time we use the same screen coords — caller is responsible for ensuring SU
-- window is in the same screen position as recording.
local eventtap = require('hs.eventtap')
local types    = eventtap.event.types
local kc       = hs.keycodes.map

local M = {}

local MOUSE_MOVE_MIN_MS = 33 -- ~30 Hz throttle

local active_tap = nil
local current_seq = nil
local last_event_ts = nil
local last_move_ts = 0
local on_change_callback = nil

-- Keycodes that we MUST NOT record (our own hotkeys). Caller sets these.
local hotkey_blocklist = {}

local function now_ms()
  return hs.timer.secondsSinceEpoch() * 1000
end

local function modifier_array(flags)
  local out = {}
  if flags.cmd  then table.insert(out, 'cmd')  end
  if flags.shift then table.insert(out, 'shift') end
  if flags.alt  then table.insert(out, 'alt')  end
  if flags.ctrl then table.insert(out, 'ctrl') end
  if flags.fn   then table.insert(out, 'fn')   end
  return out
end

local function append_event(evt)
  if not current_seq then return end
  local t = now_ms()
  if last_event_ts then
    evt.pause_before_ms = math.floor(t - last_event_ts + 0.5)
  else
    evt.pause_before_ms = 0
  end
  last_event_ts = t

  evt.id = string.format('evt_%04d', #current_seq.events + 1)
  table.insert(current_seq.events, evt)

  if on_change_callback then
    on_change_callback(#current_seq.events)
  end
end

local function key_name_for_keycode(keycode)
  for name, code in pairs(kc) do
    if type(code) == 'number' and code == keycode and #name <= 12 then
      return name
    end
  end
  return tostring(keycode)
end

local function is_hotkey_combo(keycode, flags)
  for _, h in ipairs(hotkey_blocklist) do
    if h.keycode == keycode
       and (flags.cmd  or false) == (h.cmd  or false)
       and (flags.alt  or false) == (h.alt  or false)
       and (flags.ctrl or false) == (h.ctrl or false)
       and (flags.shift or false) == (h.shift or false) then
      return true
    end
  end
  return false
end

local function handle_event(e)
  local etype = e:getType()
  local pos = e:location()
  local flags = e:getFlags()

  if etype == types.leftMouseDown or etype == types.leftMouseUp
  or etype == types.rightMouseDown or etype == types.rightMouseUp
  or etype == types.otherMouseDown or etype == types.otherMouseUp then
    local button = 'left'
    if etype == types.rightMouseDown or etype == types.rightMouseUp then
      button = 'right'
    elseif etype == types.otherMouseDown or etype == types.otherMouseUp then
      button = 'middle'
    end
    local kind = (etype == types.leftMouseDown
               or etype == types.rightMouseDown
               or etype == types.otherMouseDown) and 'mouse_down' or 'mouse_up'
    append_event({
      type = kind,
      button = button,
      x = math.floor(pos.x + 0.5),
      y = math.floor(pos.y + 0.5),
      modifiers = modifier_array(flags),
    })

  elseif etype == types.mouseMoved
      or etype == types.leftMouseDragged
      or etype == types.rightMouseDragged
      or etype == types.otherMouseDragged then
    local t = now_ms()
    if t - last_move_ts >= MOUSE_MOVE_MIN_MS then
      last_move_ts = t
      append_event({
        type = 'mouse_move',
        x = math.floor(pos.x + 0.5),
        y = math.floor(pos.y + 0.5),
      })
    end

  elseif etype == types.keyDown or etype == types.keyUp then
    local keycode = e:getKeyCode()
    if is_hotkey_combo(keycode, flags) then return false end
    append_event({
      type = etype == types.keyDown and 'key_down' or 'key_up',
      key  = key_name_for_keycode(keycode),
      keycode = keycode,
      modifiers = modifier_array(flags),
    })

  elseif etype == types.scrollWheel then
    -- API: scrollWheelEventDeltaAxis1 (vertical), Axis2 (horizontal)
    local dy = e:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1) or 0
    local dx = e:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis2) or 0
    if dx ~= 0 or dy ~= 0 then
      append_event({
        type = 'scroll',
        x = math.floor(pos.x + 0.5),
        y = math.floor(pos.y + 0.5),
        scroll_dx = dx,
        scroll_dy = dy,
      })
    end
  end

  return false -- never swallow events
end

function M.set_hotkey_blocklist(list)
  hotkey_blocklist = list or {}
end

function M.start(sequence, opts)
  if active_tap then return false, 'already recording' end
  current_seq = sequence
  last_event_ts = nil
  last_move_ts = 0
  on_change_callback = (opts or {}).on_change

  -- Initial intro pause = 0; first real event timestamps from now.
  last_event_ts = now_ms()

  active_tap = eventtap.new({
    types.leftMouseDown, types.leftMouseUp,
    types.rightMouseDown, types.rightMouseUp,
    types.otherMouseDown, types.otherMouseUp,
    types.mouseMoved,
    types.leftMouseDragged, types.rightMouseDragged, types.otherMouseDragged,
    types.keyDown, types.keyUp,
    types.scrollWheel,
  }, handle_event)
  active_tap:start()
  return true
end

function M.stop()
  if not active_tap then return false, 'not recording' end
  active_tap:stop()
  active_tap = nil
  local seq = current_seq
  current_seq = nil
  return true, seq
end

function M.is_recording()
  return active_tap ~= nil
end

function M.event_count()
  if not current_seq then return 0 end
  return #current_seq.events
end

return M
