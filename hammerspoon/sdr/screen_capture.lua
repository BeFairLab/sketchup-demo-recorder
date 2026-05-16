-- screen_capture.lua — screencapture -V wrapper.
--
-- screencapture supports -V <duration> for fixed-length recording and -R x,y,w,h
-- for a screen region. We use a child task; on stop_now we send SIGTERM and
-- wait for the file to be flushed.
local M = {}

local current_task = nil
local current_path = nil
local current_started_at = nil

-- Start an unbounded recording of region. screencapture has no "until stopped"
-- mode for video — so we use a very long -V duration (3600s) and kill the
-- process when we want to stop. screencapture writes a valid mov on SIGTERM.
function M.start(region, output_path, max_seconds)
  if current_task then return false, 'recording already in progress' end

  local seconds = max_seconds or 600

  -- Determine display index by finding which display contains the region center.
  local cx = region.x + region.w / 2
  local cy = region.y + region.h / 2
  local display_index = 1
  for i, scr in ipairs(hs.screen.allScreens()) do
    local f = scr:frame()
    if cx >= f.x and cx < f.x + f.w and cy >= f.y and cy < f.y + f.h then
      display_index = i
      break
    end
  end

  local args = {
    '-V', tostring(seconds),
    '-D', tostring(display_index),
    '-T', '0',
    '-x',
    '-R', string.format('%d,%d,%d,%d', region.x, region.y, region.w, region.h),
    output_path,
  }

  -- Ensure parent dir exists
  hs.fs.mkdir(string.match(output_path, '(.+)/[^/]+$') or '.')

  current_task = hs.task.new('/usr/sbin/screencapture', function(exitCode, stdOut, stdErr)
    current_task = nil
  end, args)

  current_path = output_path
  current_started_at = hs.timer.secondsSinceEpoch()

  local ok = current_task:start()
  if not ok then
    current_task = nil
    return false, 'failed to start screencapture'
  end

  return true
end

function M.stop()
  if not current_task then return false, 'not recording' end
  local task = current_task
  local path = current_path
  current_task = nil
  current_path = nil

  -- SIGTERM and let it flush.
  task:terminate()

  -- Wait briefly for the file to appear / settle.
  local target = hs.timer.secondsSinceEpoch() + 5
  while hs.timer.secondsSinceEpoch() < target do
    local f = io.open(path, 'r')
    if f then
      f:seek('end')
      local size = f:seek()
      f:close()
      if size and size > 1024 then break end
    end
    hs.timer.usleep(100000)
  end

  return true, path
end

function M.is_recording()
  return current_task ~= nil
end

function M.elapsed()
  if not current_started_at then return 0 end
  return hs.timer.secondsSinceEpoch() - current_started_at
end

return M
