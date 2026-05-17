-- screen_capture.lua — wrap `screencapture -V` for fixed-duration region recording.
--
-- screencapture's -V mode runs for a fixed number of seconds then exits with
-- a valid .mov. We give it the exact total length up-front and DO NOT
-- terminate it early — SIGTERM tends to leave an invalid/empty file.
local M = {}

local current_task   = nil
local current_path   = nil
local current_started = nil
local current_seconds = nil

local function display_for_region(region)
  local cx = region.x + region.w / 2
  local cy = region.y + region.h / 2
  for i, scr in ipairs(hs.screen.allScreens()) do
    local f = scr:frame()
    if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
      return i
    end
  end
  return 1
end

-- region {x,y,w,h} in logical points (matches what screencapture -R expects).
-- output_path: full path to write the .mov file.
-- seconds: fixed recording duration.
-- on_done: optional callback(exitCode, file_path)
function M.start(region, output_path, seconds, on_done)
  if current_task then return false, 'recording already in progress' end
  if not region or region.w <= 0 or region.h <= 0 then
    return false, 'invalid region ' .. hs.inspect(region)
  end

  -- Clamp region to the display it sits on. screencapture silently writes a
  -- 0-byte file if the region extends past display bounds — fatal for
  -- portrait Reels captures on small displays.
  local cx = region.x + region.w / 2
  local cy = region.y + region.h / 2
  local screen = nil
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:frame()
    if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
      screen = s; break
    end
  end
  if screen then
    local sf = screen:frame()
    local x = math.max(sf.x, region.x)
    local y = math.max(sf.y, region.y)
    local w = math.min(region.w, sf.x + sf.w - x)
    local h = math.min(region.h, sf.y + sf.h - y)
    if x ~= region.x or y ~= region.y or w ~= region.w or h ~= region.h then
      hs.printf('screencapture: region clamped %d,%d %dx%d → %d,%d %dx%d',
        region.x, region.y, region.w, region.h, x, y, w, h)
      region = { x = x, y = y, w = w, h = h }
    end
  end

  -- Round to integers (screencapture parses int).
  region = { x = math.floor(region.x + 0.5), y = math.floor(region.y + 0.5),
             w = math.floor(region.w + 0.5), h = math.floor(region.h + 0.5) }

  seconds = math.max(2, math.floor(seconds + 0.5))

  -- Ensure parent dir exists.
  local dir = output_path:match('(.+)/[^/]+$')
  if dir then hs.fs.mkdir(dir) end

  -- Remove any pre-existing file at this path (screencapture will not overwrite).
  os.remove(output_path)

  local display_index = display_for_region(region)
  local args = {
    '-V', tostring(seconds),
    '-D', tostring(display_index),
    '-T', '0',
    '-x',
    '-R', string.format('%d,%d,%d,%d', region.x, region.y, region.w, region.h),
    output_path,
  }

  local path = output_path
  current_path = path
  current_started = hs.timer.secondsSinceEpoch()
  current_seconds = seconds

  current_task = hs.task.new('/usr/sbin/screencapture', function(exitCode, stdOut, stdErr)
    current_task = nil
    local final_path = path
    local size = 0
    local f = io.open(final_path, 'r')
    if f then f:seek('end'); size = f:seek() or 0; f:close() end
    hs.printf('screencapture exit=%s size=%d  stderr=%q  stdout=%q  path=%s',
      tostring(exitCode), size, tostring(stdErr or ''), tostring(stdOut or ''), final_path)
    if on_done then on_done(exitCode, final_path, size, stdErr) end
  end, args)

  local ok = current_task:start()
  if not ok then
    current_task = nil
    current_path = nil
    return false, 'failed to start screencapture'
  end

  hs.printf('screencapture START args=%s', hs.inspect(args))
  hs.printf('screencapture region=%d,%d %dx%d   display=%d   duration=%ds   out=%s',
    region.x, region.y, region.w, region.h, display_index, seconds, path)
  return true, path
end

function M.is_recording()
  return current_task ~= nil
end

function M.elapsed()
  if not current_started then return 0 end
  return hs.timer.secondsSinceEpoch() - current_started
end

function M.remaining()
  if not current_started or not current_seconds then return 0 end
  return math.max(0, current_seconds - M.elapsed())
end

return M
