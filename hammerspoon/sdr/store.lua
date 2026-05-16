-- store.lua — sequence JSON persistence.
local json = require('hs.json')

local M = {}

-- Resolved at init() — caller passes the directory.
local store_dir = nil

function M.init(dir)
  store_dir = dir
  -- Ensure dir exists.
  hs.fs.mkdir(dir)
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
