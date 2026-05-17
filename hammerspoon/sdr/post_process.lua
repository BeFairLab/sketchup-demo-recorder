-- post_process.lua — ffmpeg post-processing for captured .mov files.
-- All operations run async via hs.task. Callback signature: (ok, out_path, msg).
local M = {}

local FFMPEG = '/opt/homebrew/bin/ffmpeg'

local function ffmpeg_run(args, out_path, on_done)
  hs.printf('ffmpeg_run args=%s', hs.inspect(args))
  local task = hs.task.new(FFMPEG, function(exitCode, stdOut, stdErr)
    hs.printf('ffmpeg done exit=%s out=%s stderr=%q',
      tostring(exitCode), out_path, tostring(stdErr or ''))
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
-- opts.rescale_youtube = { w, h } and opts.rescale_reels = { w, h } —
-- optional per-variant rescale targets applied after crop.
--
-- IMPORTANT: SketchUp clamps viewport height to fit the display, so the
-- captured .mov can be SMALLER than the requested preset (e.g. universal_2160
-- requested 2160×2160 px but lands on 2160×2044 on a 1117pt-high display).
-- Hardcoded crop offsets miss center. We use ffmpeg expressions so the crop
-- is centered relative to the ACTUAL input dimensions (iw/ih), and clamped
-- so we never request a crop larger than the source — that would 0-byte the
-- output mp4.
function M.split_universal(in_path, preset, opts, on_done)
  opts = opts or {}
  local crops = {}
  if preset == 'universal_1920' then
    crops = {
      { name = 'youtube', target_w = 1920, target_h = 1080, rescale = opts.rescale_youtube },
      { name = 'reels',   target_w = 1080, target_h = 1920, rescale = opts.rescale_reels   },
    }
  elseif preset == 'universal_2160' then
    crops = {
      { name = 'youtube', target_w = 1920, target_h = 1080, rescale = opts.rescale_youtube },
      { name = 'reels',   target_w = 1080, target_h = 1920, rescale = opts.rescale_reels   },
    }
  else
    on_done(false, in_path, 'unknown universal preset: ' .. tostring(preset))
    return
  end

  -- Build adaptive filters: clamp target to source, center the crop.
  for _, c in ipairs(crops) do
    local w_expr = string.format('min(iw,%d)', c.target_w)
    local h_expr = string.format('min(ih,%d)', c.target_h)
    c.filter = string.format('crop=%s:%s:(iw-%s)/2:(ih-%s)/2',
      w_expr, h_expr, w_expr, h_expr)
  end

  -- Probe input dimensions via ffprobe so we can warn about clamp losses.
  local probe = hs.task.new('/opt/homebrew/bin/ffprobe', function(_, stdOut, _)
    local w, h = stdOut:match('(%d+)[xX](%d+)')
    hs.printf('split_universal: source=%sx%s preset=%s', tostring(w), tostring(h), tostring(preset))
    for _, c in ipairs(crops) do
      if w and h and (c.target_w > tonumber(w) or c.target_h > tonumber(h)) then
        hs.printf('  ⚠ %s crop %dx%d larger than source %sx%s → ffmpeg will clamp to source',
          c.name, c.target_w, c.target_h, w, h)
      end
    end
  end, {
    '-v', 'error', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height',
    '-of', 'csv=s=x:p=0',
    in_path,
  })
  probe:start()

  local outputs = {}
  local pending = #crops
  for _, c in ipairs(crops) do
    local vf = c.filter
    local suffix = '_' .. c.name
    if c.rescale and c.rescale.w and c.rescale.h then
      vf = vf .. string.format(',scale=%d:%d:flags=lanczos', c.rescale.w, c.rescale.h)
      suffix = suffix .. string.format('_%dx%d', c.rescale.w, c.rescale.h)
    end
    local out_path = suffix_path(in_path, suffix, 'mp4')
    ffmpeg_run({
      '-y', '-loglevel', 'error',
      '-i', in_path,
      '-vf', vf,
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
