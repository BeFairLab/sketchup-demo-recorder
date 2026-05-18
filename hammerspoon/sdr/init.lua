-- init.lua — sketchup-demo-recorder entry.
-- User loads from ~/.hammerspoon/init.lua via:
--   sdr = require('sdr')
--   sdr.start({ repo_root = '/Users/me/Code/sketchup-demo-recorder' })

local store    = require('sdr.store')
local recorder = require('sdr.recorder')
local replayer = require('sdr.replayer')
local sizer    = require('sdr.window_sizer')
local capture  = require('sdr.screen_capture')
local bridge   = require('sdr.companion_bridge')
local ui       = require('sdr.ui')
local post     = require('sdr.post_process')

local M = {}

local config = {}
local current_seq_name = nil
local current_seq = nil
local recording_overlay = nil
local menubar_icon = nil

-- ─── Helpers ─────────────────────────────────────────────────────────

local function set_status(status)
  if menubar_icon then
    local icons = { idle = '🟢', recording = '🔴', replaying = '🟣', capturing = '⏺️' }
    menubar_icon:setTitle(icons[status] or '⚪️')
  end
  ui.push('status', { status = status })
end

local function notify(title, body)
  hs.notify.new({ title = title, informativeText = body or '' }):send()
end

local SETTINGS_KEY_ACTIVE = 'sdr.active_sequence_name'

-- Compute screen-space rects where recorder should IGNORE mouse events so
-- our own UI / system menubar clicks never end up in the captured sequence.
local MENUBAR_PT = 25
local function compute_dead_zones()
  local zones = {}
  -- macOS menubar across every screen.
  for _, s in ipairs(hs.screen.allScreens()) do
    local f = s:fullFrame()
    table.insert(zones, { x = f.x, y = f.y, w = f.w, h = MENUBAR_PT })
  end
  -- Our UI window, if open.
  local frame = ui.is_open() and ui.window_frame and ui.window_frame()
  if frame then table.insert(zones, frame) end
  return zones
end

local function ensure_seq(name)
  if not name or name == '' or name == 'nil' then
    error('ensure_seq: invalid name ' .. tostring(name))
  end
  current_seq_name = name
  hs.settings.set(SETTINGS_KEY_ACTIVE, name)
  local seq = store.load(name)
  if not seq then
    seq = store.new_sequence(name)
    store.save(name, seq)
  end
  current_seq = seq
  return seq
end

-- For universal presets, the keystroke label sits at the bottom-left of the
-- intersection of YouTube + Reels safe areas (= smallest dimension of each).
-- For all other presets, bottom-left of the recording region itself.
-- Returns absolute screen coords {x, y} or nil.
local function keystroke_anchor_for(vp)
  if not vp or not vp.region then return nil end
  local r = vp.region
  local pad = 18
  local label_h = 44
  -- For universal presets, anchor at the bottom-left of the YouTube∩Reels
  -- intersection (smaller of the two dimensions per axis = safe across both).
  local intersect_w, intersect_h = nil, nil
  if vp.preset == 'universal_1920' or vp.preset == 'universal_2160' then
    intersect_w, intersect_h = 540, 540
  elseif vp.preset == 'universal_custom' then
    local uc = vp.universal_custom or {}
    local yt = uc.youtube or { w = 1920, h = 1080 }
    local rl = uc.reels   or { w = 1080, h = 1920 }
    intersect_w = math.min(yt.w, rl.w) / 2
    intersect_h = math.min(yt.h, rl.h) / 2
  end
  if intersect_w and intersect_h then
    local ix = r.x + (r.w - intersect_w) / 2
    local iy = r.y + (r.h - intersect_h) / 2
    return { x = ix + pad, y = iy + intersect_h - pad - label_h }
  end
  return { x = r.x + pad, y = r.y + r.h - pad - label_h }
end

-- Safe-frame overlays for crop-target previewing. Returns nil for non-universal
-- presets. Sizes in LOGICAL POINTS (= pixels / retina_scale). Centered inside
-- the recording region.
local function safe_frames_for(vp)
  if not vp then return nil end
  -- Retina = 2; convert pixel dims to canvas points by dividing by 2.
  if vp.preset == 'universal_1920' or vp.preset == 'universal_2160' then
    return {
      { name = 'YouTube 16:9', w = 960, h = 540, color = { 1.0, 0.85, 0.20 } },
      { name = 'Reels 9:16',   w = 540, h = 960, color = { 1.0, 0.35, 0.35 } },
    }
  elseif vp.preset == 'universal_custom' then
    local uc = vp.universal_custom or {}
    local yt = uc.youtube or { w = 1920, h = 1080 }
    local rl = uc.reels   or { w = 1080, h = 1920 }
    return {
      { name = 'YouTube', w = yt.w / 2, h = yt.h / 2, color = { 1.0, 0.85, 0.20 } },
      { name = 'Reels',   w = rl.w / 2, h = rl.h / 2, color = { 1.0, 0.35, 0.35 } },
    }
  end
  return nil
end

-- Auto-load the last-used sequence on boot. Silent if missing.
local function restore_active_sequence()
  local name = hs.settings.get(SETTINGS_KEY_ACTIVE)
  if not name then return end
  local seq = store.load(name)
  if seq then
    current_seq_name = name
    current_seq = seq
    hs.printf('SDR restored active sequence: %s (%d events)', name, #(seq.events or {}))
  end
end

-- ─── UI handlers ─────────────────────────────────────────────────────

local function register_handlers()
  ui.register('list_sequences', function(_)
    return store.list()
  end)

  ui.register('list_sequences_with_meta', function(_)
    local out = {}
    for _, name in ipairs(store.list()) do
      local seq = store.load(name)
      table.insert(out, {
        name = name,
        preset_name = seq and seq.preset_name or nil,
        events = seq and #(seq.events or {}) or 0,
      })
    end
    return out
  end)

  ui.register('get_active_sequence', function(_)
    return { name = current_seq_name, sequence = current_seq }
  end)

  -- Update current_seq in memory without disk write (used by play/capture
  -- so unsaved UI edits take effect immediately).
  ui.register('set_active_sequence', function(payload)
    if not payload or not payload.sequence then return { error = 'no sequence' } end
    current_seq = payload.sequence
    current_seq_name = payload.sequence.name or current_seq_name
    return { ok = true }
  end)

  ui.register('load_sequence', function(payload)
    local seq = ensure_seq(payload.name)
    -- Auto-apply the linked preset if one is referenced and exists.
    if seq.preset_name then
      local preset = store.load_preset(seq.preset_name)
      if preset then
        seq.viewport = preset.viewport
        seq.chrome_offsets = preset.chrome_offsets
        seq.playback = preset.playback
        seq.output = preset.output
      end
    end
    current_seq = seq
    return seq
  end)

  -- Save the events + preset_name link. Viewport/playback/output live in
  -- the linked preset file and are reloaded from there on load_sequence.
  -- This is the ONLY way to persist timeline changes.
  ui.register('save_timeline', function(payload)
    local seq = payload.sequence
    if not seq then return { error = 'no sequence' } end
    local existing = store.load(seq.name) or store.new_sequence(seq.name)
    existing.events = seq.events or {}
    existing.name = seq.name
    -- BUGFIX: persist the preset link too. Without this, header preset changes
    -- never stuck across sessions.
    existing.preset_name = seq.preset_name or existing.preset_name
    store.save(seq.name, existing)
    current_seq = existing
    current_seq_name = seq.name
    hs.settings.set(SETTINGS_KEY_ACTIVE, seq.name)
    return { saved = true }
  end)

  -- Save preset settings as standalone reusable template.
  ui.register('save_preset', function(payload)
    if not payload or not payload.name or not payload.sequence then
      return { error = 'preset name + sequence required' }
    end
    local ok, err = store.save_preset(payload.name, payload.sequence)
    if not ok then return { error = err } end
    return { saved = true, name = payload.name }
  end)

  ui.register('list_presets', function(_)
    return store.list_presets()
  end)

  -- Read a preset's content without touching current_seq. For the Preset
  -- Settings tab, which is decoupled from playback/capture state.
  ui.register('get_preset', function(payload)
    if not payload or not payload.name then return { error = 'name required' } end
    local p = store.load_preset(payload.name)
    if not p then return { error = 'not found' } end
    return p
  end)

  ui.register('apply_preset', function(payload)
    if not payload or not payload.name then return { error = 'preset name required' } end
    local preset = store.load_preset(payload.name)
    if not preset then return { error = 'preset not found' } end
    local mismatch = nil
    -- Build a draft sequence on the fly if none is loaded, so the caller can
    -- still examine the preset values via the returned sequence.
    if not current_seq then
      current_seq = store.new_sequence('__draft__')
      current_seq_name = nil -- not persisted
    elseif current_seq.preset_name and current_seq.preset_name ~= payload.name then
      mismatch = 'this timeline expects preset "' .. current_seq.preset_name ..
                 '"; applying "' .. payload.name .. '" instead'
    end
    current_seq.viewport = preset.viewport
    current_seq.chrome_offsets = preset.chrome_offsets
    current_seq.playback = preset.playback
    current_seq.output = preset.output
    current_seq.preset_name = payload.name
    return { applied = true, sequence = current_seq, mismatch = mismatch }
  end)

  -- ── Management ─────────────────────────────────────────────────
  ui.register('delete_sequence', function(payload)
    if not payload or not payload.name then return { error = 'name required' } end
    store.delete(payload.name)
    if current_seq_name == payload.name then current_seq = nil; current_seq_name = nil end
    return { deleted = true }
  end)

  ui.register('rename_sequence', function(payload)
    if not payload or not payload.old or not payload.new then return { error = 'old + new required' } end
    local ok, err = store.rename(payload.old, payload.new)
    if not ok then return { error = tostring(err) } end
    if current_seq_name == payload.old then
      current_seq_name = payload.new
      if current_seq then current_seq.name = payload.new end
      hs.settings.set(SETTINGS_KEY_ACTIVE, payload.new)
    end
    return { renamed = true }
  end)

  ui.register('export_sequence', function(payload)
    if not payload or not payload.name then return { error = 'name required' } end
    local src = store.path_for(payload.name)
    local dest = (payload.dest_dir or (os.getenv('HOME') .. '/Desktop')) ..
                 '/' .. payload.name .. '.json'
    hs.task.new('/bin/cp', function() end, { src, dest }):start()
    return { exported = dest }
  end)

  ui.register('delete_preset', function(payload)
    if not payload or not payload.name then return { error = 'name required' } end
    store.delete_preset(payload.name)
    return { deleted = true }
  end)

  ui.register('rename_preset', function(payload)
    if not payload or not payload.old or not payload.new then return { error = 'old + new required' } end
    local ok, err = store.rename_preset(payload.old, payload.new)
    if not ok then return { error = tostring(err) } end
    return { renamed = true }
  end)

  ui.register('duplicate_preset', function(payload)
    if not payload or not payload.src or not payload.dest then return { error = 'src + dest required' } end
    local ok, err = store.duplicate_preset(payload.src, payload.dest)
    if not ok then return { error = tostring(err) } end
    return { duplicated = true }
  end)

  ui.register('export_preset', function(payload)
    if not payload or not payload.name then return { error = 'name required' } end
    local src = store.preset_path_for(payload.name)
    local dest = (payload.dest_dir or (os.getenv('HOME') .. '/Desktop')) ..
                 '/preset-' .. payload.name .. '.json'
    hs.task.new('/bin/cp', function() end, { src, dest }):start()
    return { exported = dest }
  end)

  ui.register('new_sequence', function(payload)
    return ensure_seq(payload.name)
  end)

  ui.register('apply_viewport', function(payload)
    local seq = payload.sequence or current_seq
    if not seq then return { error = 'no sequence loaded' } end
    local region, err, win_frame = sizer.apply(seq.viewport, seq.chrome_offsets)
    if err then return { error = err } end
    seq.viewport.region = region
    seq.viewport.window_position = win_frame -- for record-time anchor parity
    current_seq = seq
    if current_seq_name then store.save(current_seq_name, seq) end
    return { region = region, window_position = win_frame }
  end)

  ui.register('show_overlay', function(payload)
    if not current_seq or not current_seq.viewport or not current_seq.viewport.region then
      return { shown = false, error = 'apply viewport first' }
    end
    -- Prefer shift passed in by UI (live edit) over saved value.
    local shift = (payload and payload.shift)
               or current_seq.viewport.overlay_shift
               or { dx = 0, dy = 0 }
    current_seq.viewport.overlay_shift = shift
    sizer.show_overlay(current_seq.viewport.region, safe_frames_for(current_seq.viewport), shift)
    return { shown = true }
  end)

  ui.register('hide_overlay', function(_)
    sizer.hide_overlay()
    return { hidden = true }
  end)

  ui.register('ping_companion', function(_)
    local r, e = bridge.ping()
    return { result = r, error = e }
  end)

  ui.register('start_record', function(payload)
    if not current_seq then return { error = 'load a sequence first' } end
    local append = payload and payload.append == true
    if not append then current_seq.events = {} end
    set_status('recording')
    recorder.set_dead_zones(compute_dead_zones())
    recorder.start(current_seq, {
      append = append,
      on_change = function(n)
        ui.push('event_count', { count = n })
      end
    })
    return { recording = true, append = append }
  end)

  ui.register('stop_record', function(_)
    local ok, seq = recorder.stop()
    set_status('idle')
    -- Push the new events but do NOT auto-save; UI marks dirty for explicit Save.
    if seq then ui.push('sequence_updated', seq) end
    return { stopped = true, events = current_seq and #current_seq.events or 0 }
  end)

  ui.register('play', function(payload)
    if not current_seq then return { error = 'no sequence' } end
    local seq = payload.sequence or current_seq
    seq.playback = seq.playback or {}
    seq.playback.keystroke_anchor = keystroke_anchor_for(seq.viewport)
    local app = hs.application.find('SketchUp')
    if app then app:activate() end
    set_status('replaying')
    -- Playback-defined delays override caller defaults.
    local lead = seq.playback.pre_delay_ms or payload.lead_ms or 800
    local tail = seq.playback.post_delay_ms or payload.tail_ms or 0
    replayer.play(seq, {
      lead_ms = lead,
      tail_ms = tail,
      on_progress = function(i, n, e)
        ui.push('replay_progress', { i = i, n = n, type = e.type })
      end,
      on_done = function()
        set_status('idle')
        ui.push('replay_done', {})
      end,
    })
    return { playing = true }
  end)

  ui.register('capture_and_play', function(payload)
    if not current_seq then return { error = 'no sequence' } end
    local seq = current_seq
    if not seq.viewport.region or seq.viewport.region.w == 0 then
      return { error = 'apply viewport first' }
    end

    local pb_pre  = (seq.playback or {}).pre_delay_ms
    local pb_post = (seq.playback or {}).post_delay_ms
    local lead = pb_pre  or payload.lead_ms or 1000
    local tail = pb_post or payload.tail_ms or 1000
    local out_dir = payload.out_dir or (os.getenv('HOME') .. '/Desktop')
    hs.fs.mkdir(out_dir)
    local out_path = string.format('%s/%s_%s.mov', out_dir, seq.name, os.date('%Y%m%d_%H%M%S'))

    -- Timeline:
    --   t=0           start screencapture
    --   t=PRE_ROLL    bring SU foreground, start replay (lead included)
    --   t=...         replay finishes
    --   t=END         capture stops naturally
    local PRE_ROLL = 0.7 -- seconds from capture start until replay begins
    local POST_ROLL = math.max(0.3, (tail / 1000))
    local SAFETY_PAD = 2.0 -- extra so any duration miscalc doesn't truncate the take
    local total_replay_s = replayer.total_duration_ms(seq, lead, 0) / 1000
    local cap_seconds = PRE_ROLL + total_replay_s + POST_ROLL + SAFETY_PAD

    set_status('capturing')

    -- Inject computed keystroke anchor for this capture.
    seq.playback = seq.playback or {}
    seq.playback.keystroke_anchor = keystroke_anchor_for(seq.viewport)

    -- Hide overlay so it's NOT baked into the captured video.
    sizer.suppress_overlay()

    local ok, err = capture.start(seq.viewport.region, out_path, cap_seconds, function(exitCode, path, size)
      sizer.resume_overlay()
      if size <= 0 then
        set_status('idle')
        ui.push('capture_done', { path = path, error = 'empty file (exit=' .. tostring(exitCode) .. ')' })
        notify('SDR capture FAILED', path .. ' empty')
        return
      end

      -- Run post-processing per output settings.
      local out = seq.output or {}
      local preset = seq.viewport and seq.viewport.preset

      local rescale_arg = nil
      if out.rescale and out.rescale_w and out.rescale_h then
        rescale_arg = { w = out.rescale_w, h = out.rescale_h }
      end
      local rs_yt = (out.rescale_youtube_w and out.rescale_youtube_h)
        and { w = out.rescale_youtube_w, h = out.rescale_youtube_h }
        or rescale_arg
      local rs_rl = (out.rescale_reels_w and out.rescale_reels_h)
        and { w = out.rescale_reels_w, h = out.rescale_reels_h }
        or rescale_arg

      hs.printf('capture_done: preset=%s auto_crop=%s rescale=%s out=%s',
        tostring(preset), tostring(out.auto_crop_universal),
        tostring(out.rescale), hs.inspect(out))

      if out.auto_crop_universal and (preset == 'universal_1920' or preset == 'universal_2160' or preset == 'universal_custom') then
        set_status('capturing')
        local custom_crops = nil
        if preset == 'universal_custom' and seq.viewport and seq.viewport.universal_custom then
          custom_crops = seq.viewport.universal_custom
        end
        post.split_universal(path, preset, {
          rescale_youtube = rs_yt,
          rescale_reels   = rs_rl,
          custom_crops    = custom_crops,
        }, function(_, _, outputs)
          set_status('idle')
          ui.push('capture_done', { path = path, size = size, post = outputs })
          local msg = path .. '  +'
          for _, o in ipairs(outputs or {}) do msg = msg .. ' ' .. o.name end
          notify('SDR capture + crops', msg)
        end)
      elseif rescale_arg then
        post.rescale(path, rescale_arg, function(ok2, out_path)
          set_status('idle')
          ui.push('capture_done', { path = path, size = size, scaled = ok2 and out_path or nil })
          notify('SDR capture + scaled', (ok2 and out_path) or path)
        end)
      else
        set_status('idle')
        ui.push('capture_done', { path = path, size = size })
        notify('SDR capture done', path .. ' ' .. math.floor(size / 1024) .. 'KB')
      end
    end)
    if not ok then
      set_status('idle')
      sizer.resume_overlay()
      return { error = 'capture: ' .. err }
    end

    local app = hs.application.find('SketchUp')
    if app then app:activate() end

    hs.timer.doAfter(PRE_ROLL, function()
      replayer.play(seq, {
        lead_ms = lead,
        tail_ms = 0,
        on_progress = function(i, n, e)
          ui.push('replay_progress', { i = i, n = n, type = e.type })
        end,
        on_done = function()
          ui.push('replay_done', {})
          -- We do NOT stop capture here. It runs out its -V duration so
          -- the file is flushed cleanly. The on_done above will fire.
        end,
      })
    end)

    return { capturing = true, output = out_path, expected_seconds = cap_seconds }
  end)
end

-- ─── Hotkeys ─────────────────────────────────────────────────────────

local hotkeys = {}

local function bind_hotkeys()
  -- ⌃⌥⌘R — fresh record (toggle). ⌃⌥⌘E — continue (append) record.
  local function bind_record(modes_extend)
    return function()
      if recorder.is_recording() then
        local _, seq = recorder.stop()
        set_status('idle')
        -- Don't auto-save: hand seq back to UI which will mark dirty so user
        -- explicitly clicks 'Save changes'. Prevents accidental overwrites.
        notify('SDR', 'Recording stopped (' .. (seq and #seq.events or 0) .. ' events) — Save to persist')
        ui.push('sequence_updated', seq)
      else
        if not current_seq then notify('SDR', 'Load a sequence first'); return end
        if not modes_extend then current_seq.events = {} end
        recorder.set_dead_zones(compute_dead_zones())
        recorder.start(current_seq, {
          append = modes_extend,
          on_change = function(n) ui.push('event_count', { count = n }) end
        })
        set_status('recording')
        notify('SDR', modes_extend and 'Continuing recording' or 'Recording started')
      end
    end
  end
  table.insert(hotkeys, hs.hotkey.bind({'ctrl', 'alt', 'cmd'}, 'r', bind_record(false)))
  table.insert(hotkeys, hs.hotkey.bind({'ctrl', 'alt', 'cmd'}, 'e', bind_record(true)))

  -- ⌃⌥⌘V — toggle window
  table.insert(hotkeys, hs.hotkey.bind({'ctrl', 'alt', 'cmd'}, 'v', function()
    if ui.is_open() then ui.close() else ui.open(config.repo_root) end
  end))

  -- ⌃⌥⌘P — replay only
  table.insert(hotkeys, hs.hotkey.bind({'ctrl', 'alt', 'cmd'}, 'p', function()
    if not current_seq then return end
    replayer.play(current_seq, {
      on_done = function() set_status('idle') end,
    })
    set_status('replaying')
  end))

  recorder.set_hotkey_blocklist({
    { keycode = hs.keycodes.map['r'], cmd = true, alt = true, ctrl = true },
    { keycode = hs.keycodes.map['e'], cmd = true, alt = true, ctrl = true },
    { keycode = hs.keycodes.map['v'], cmd = true, alt = true, ctrl = true },
    { keycode = hs.keycodes.map['p'], cmd = true, alt = true, ctrl = true },
  })
end

-- ─── Menubar ─────────────────────────────────────────────────────────

local function build_menubar()
  menubar_icon = hs.menubar.new()
  menubar_icon:setTitle('🟢')
  menubar_icon:setMenu(function()
    return {
      { title = 'Open Recorder…', fn = function() ui.open(config.repo_root) end },
      { title = '-' },
      { title = 'Record toggle (⌃⌥⌘R)', disabled = true },
      { title = 'Replay (⌃⌥⌘P)',        disabled = true },
      { title = 'Show/Hide UI (⌃⌥⌘V)',  disabled = true },
      { title = '-' },
      { title = 'Ping Companion', fn = function()
        local r, e = bridge.ping()
        notify('SDR Companion', r and ('OK: ' .. tostring(r)) or ('ERR: ' .. tostring(e)))
      end },
      { title = 'Reload', fn = function() hs.reload() end },
    }
  end)
end

-- ─── Public API ──────────────────────────────────────────────────────

function M.start(opts)
  config = opts or {}
  assert(config.repo_root, 'repo_root required')

  local seq_dir = config.sequences_dir or (config.repo_root .. '/sequences')
  store.init(seq_dir)

  register_handlers()
  bind_hotkeys()
  build_menubar()
  ui.start(config.repo_root)
  restore_active_sequence()
  set_status('idle')

  hs.printf('SDR started. Repo: %s   Sequences: %s', config.repo_root, seq_dir)
  return M
end

function M.open() ui.open(config.repo_root) end

return M
