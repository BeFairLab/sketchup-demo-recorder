-- store.lua — sequence JSON persistence + preset templates.
local json = require('hs.json')

local M = {}

local store_dir = nil
local presets_dir = nil

function M.init(dir, p_dir)
  store_dir = dir
  hs.fs.mkdir(dir)
  presets_dir = p_dir or (dir:gsub('/sequences$', '') .. '/presets')
  hs.fs.mkdir(presets_dir)
end

local function path_for(name)
  return string.format('%s/%s.json', store_dir, name)
end

function M.list()
  local out = {}
  if not store_dir then return out end
  for file in hs.fs.dir(store_dir) do
    if file:sub(-5) == '.json' then
      table.insert(out, file:sub(1, -6))
    end
  end
  table.sort(out)
  return out
end

function M.load(name)
  local f = io.open(path_for(name), 'r')
  if not f then return nil, 'not found' end
  local raw = f:read('*a')
  f:close()
  return json.decode(raw)
end

function M.save(name, sequence)
  sequence.name = name
  local f, err = io.open(path_for(name), 'w')
  if not f then return false, err end
  f:write(json.encode(sequence, true))
  f:close()
  return true
end

function M.delete(name)
  return os.remove(path_for(name))
end

-- ─── Presets ───────────────────────────────────────────────────────
-- A preset is { viewport, chrome_offsets, playback, output } — no events.

local function preset_path(name)
  return string.format('%s/%s.json', presets_dir, name)
end

function M.list_presets()
  local out = {}
  if not presets_dir then return out end
  for file in hs.fs.dir(presets_dir) do
    if file:sub(-5) == '.json' then table.insert(out, file:sub(1, -6)) end
  end
  table.sort(out)
  return out
end

function M.save_preset(name, sequence)
  local preset = {
    name           = name,
    viewport       = sequence.viewport,
    chrome_offsets = sequence.chrome_offsets,
    playback       = sequence.playback,
    output         = sequence.output,
  }
  local f, err = io.open(preset_path(name), 'w')
  if not f then return false, err end
  f:write(json.encode(preset, true))
  f:close()
  return true
end

function M.load_preset(name)
  local f = io.open(preset_path(name), 'r')
  if not f then return nil, 'preset not found' end
  local raw = f:read('*a'); f:close()
  return json.decode(raw)
end

function M.delete_preset(name)
  return os.remove(preset_path(name))
end

function M.new_sequence(name)
  return {
    version = 1,
    name = name,
    created_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    viewport = {
      mode = 'viewport',
      preset = 'youtube_1080p',
      width = 1920,
      height = 1080,
      region = { x = 0, y = 0, w = 1920, h = 1080 },
    },
    chrome_offsets = { top = 70, bottom = 25, left = 0, right = 0 },
    events = {},
  }
end

return M
