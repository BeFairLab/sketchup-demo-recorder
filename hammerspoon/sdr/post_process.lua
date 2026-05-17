-- post_process.lua — ffmpeg post-processing for captured .mov files.
-- All operations run async via hs.task. Callback signature: (ok, out_path, msg).
local M = {}

local FFMPEG = '/opt/homebrew/bin/ffmpeg'

local function ffmpeg_run(args, out_path, on_done)
  local task = hs.task.new(FFMPEG, function(exitCode, stdOut, stdErr)
    if exitCode == 0 then
      on_done(true, out_path, 'ok')
    else
      on_done(false, out_path, 'ffmpeg exit=' .. tostring(exitCode) .. ' ' .. (stdErr or ''))
    end
  end, args)
  task:start()
end

-- Replace extension on a path: '/x/y.mov' + '_youtube' + '.mp4' → '/x/y_youtube.mp4'
local function suffix_path(path, suffix, ext)
  local dir, name = path:match('^(.*/)([^/]+)$')
  dir = dir or ''
  name = name or path
  local base = name:match('^(.+)%.[^.]+$') or name
  return dir .. base .. suffix .. '.' .. (ext or 'mp4')
end

-- Crop+encode universal capture to YouTube (16:9) and Reels (9:16) variants.
-- preset:
--   'universal_2160' → source 2160×2160 px; YouTube center 1920×1080, Reels 1080×1920
--   'universal_2880' → source 2880×2880 px; YouTube center 2880×1620, Reels 1620×2880
--
-- Pre-condition: input is a .mov from screencapture (raw pixels matching the
-- universal preset). We let ffmpeg crop in pixel space.
function M.split_universal(in_path, preset, on_done)
  local crops = {}
  if preset == 'universal_2160' then
    crops = {
      { name = 'youtube', filter = 'crop=1920:1080:120:540' },
      { name = 'reels',   filter = 'crop=1080:1920:540:120' },
    }
  elseif preset == 'universal_2880' then
    crops = {
      { name = 'youtube', filter = 'crop=2880:1620:0:630' },
      { name = 'reels',   filter = 'crop=1620:2880:630:0' },
    }
  else
    on_done(false, in_path, 'unknown universal preset: ' .. tostring(preset))
    return
  end

  local outputs = {}
  local pending = #crops
  for _, c in ipairs(crops) do
    local out_path = suffix_path(in_path, '_' .. c.name, 'mp4')
    ffmpeg_run({
      '-y', '-loglevel', 'error',
      '-i', in_path,
      '-vf', c.filter,
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow',
      '-movflags', '+faststart',
      out_path,
    }, out_path, function(ok, path, msg)
      table.insert(outputs, { ok = ok, path = path, name = c.name, msg = msg })
      pending = pending - 1
      if pending == 0 then on_done(true, in_path, outputs) end
    end)
  end
end

-- Encode with scale filter only. target = {w, h} pixels.
function M.rescale(in_path, target, on_done)
  local out_path = suffix_path(in_path, string.format('_%dx%d', target.w, target.h), 'mp4')
  ffmpeg_run({
    '-y', '-loglevel', 'error',
    '-i', in_path,
    '-vf', string.format('scale=%d:%d:flags=lanczos', target.w, target.h),
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow',
    '-movflags', '+faststart',
    out_path,
  }, out_path, on_done)
end

-- Re-encode the source mov to mp4 (h264). Useful for QuickTime → standard mp4.
function M.transcode(in_path, on_done)
  local out_path = suffix_path(in_path, '', 'mp4')
  ffmpeg_run({
    '-y', '-loglevel', 'error',
    '-i', in_path,
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow',
    '-movflags', '+faststart',
    out_path,
  }, out_path, on_done)
end

return M
