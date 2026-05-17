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

  ui.register('get_active_sequence', function(_)
    return { name = current_seq_name, sequence = current_seq }
  end)

  ui.register('load_sequence', function(payload)
    local seq = ensure_seq(payload.name)
    return seq
  end)

  ui.register('save_sequence', function(payload)
    current_seq = payload.sequence
    current_seq_name = payload.sequence.name
    hs.settings.set(SETTINGS_KEY_ACTIVE, current_seq_name)
    store.save(current_seq_name, current_seq)
    return { saved = true }
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

  ui.register('show_overlay', function(_)
    if recording_overlay then recording_overlay:delete(); recording_overlay = nil end
    if current_seq and current_seq.viewport and current_seq.viewport.region then
      recording_overlay = sizer.show_overlay(current_seq.viewport.region)
    end
    return { shown = recording_overlay ~= nil }
  end)

  ui.register('hide_overlay', function(_)
    if recording_overlay then recording_overlay:delete(); recording_overlay = nil end
    return { hidden = true }
  end)

  ui.register('ping_companion', function(_)
    local r, e = bridge.ping()
    return { result = r, error = e }
  end)

  ui.register('start_record', function(_)
    if not current_seq then return { error = 'load a sequence first' } end
    current_seq.events = {}
    set_status('recording')
    recorder.start(current_seq, {
      on_change = function(n)
        ui.push('event_count', { count = n })
      end
    })
    return { recording = true }
  end)

  ui.register('stop_record', function(_)
    local ok, seq = recorder.stop()
    set_status('idle')
    if seq and current_seq_name then
      store.save(current_seq_name, seq)
      ui.push('sequence_updated', seq)
    end
    return { stopped = true, events = current_seq and #current_seq.events or 0 }
  end)

  ui.register('play', function(payload)
    if not current_seq then return { error = 'no sequence' } end
    local seq = payload.sequence or current_seq
    -- Bring SketchUp to foreground BEFORE replay — otherwise events go to UI.
    local app = hs.application.find('SketchUp')
    if app then app:activate() end
    set_status('replaying')
    -- Lead defaults to 800ms so SU has time to fully focus before first event.
    local lead = payload.lead_ms or 800
    replayer.play(seq, {
      lead_ms = lead,
      tail_ms = payload.tail_ms or 0,
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

    local lead = payload.lead_ms or 1000
    local tail = payload.tail_ms or 1000
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
    local total_replay_s = replayer.total_duration_ms(seq, lead, 0) / 1000
    local cap_seconds = PRE_ROLL + total_replay_s + POST_ROLL

    set_status('capturing')

    local ok, err = capture.start(seq.viewport.region, out_path, cap_seconds, function(exitCode, path, size)
      set_status('idle')
      if size <= 0 then
        ui.push('capture_done', { path = path, error = 'empty file (exit=' .. tostring(exitCode) .. ')' })
        notify('SDR capture FAILED', path .. ' empty (exit ' .. tostring(exitCode) .. ')')
      else
        ui.push('capture_done', { path = path, size = size })
        notify('SDR capture done', path .. ' ' .. math.floor(size / 1024) .. 'KB')
      end
    end)
    if not ok then
      set_status('idle')
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
  -- ⌃⌥⌘R — toggle record
  table.insert(hotkeys, hs.hotkey.bind({'ctrl', 'alt', 'cmd'}, 'r', function()
    if recorder.is_recording() then
      local _, seq = recorder.stop()
      set_status('idle')
      if seq and current_seq_name then store.save(current_seq_name, seq) end
      notify('SDR', 'Recording stopped (' .. (seq and #seq.events or 0) .. ' events)')
      ui.push('sequence_updated', seq)
    else
      if not current_seq then
        notify('SDR', 'Load a sequence first')
        return
      end
      current_seq.events = {}
      recorder.start(current_seq, {
        on_change = function(n) ui.push('event_count', { count = n }) end
      })
      set_status('recording')
      notify('SDR', 'Recording started')
    end
  end))

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

  -- Tell recorder to ignore our hotkey combos.
  recorder.set_hotkey_blocklist({
    { keycode = hs.keycodes.map['r'], cmd = true, alt = true, ctrl = true },
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
