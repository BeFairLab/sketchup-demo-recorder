-- companion_bridge.lua — file-IPC with SDR Companion SketchUp plugin.
--
-- Writes /tmp/sdr_cmd.json (caller bumps `id` so plugin detects new cmds).
-- Polls /tmp/sdr_result.json for matching `id`, returns parsed result.
local json = require('hs.json')

local M = {}

local CMD_PATH    = '/tmp/sdr_cmd.json'
local RESULT_PATH = '/tmp/sdr_result.json'

local next_id = 1

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local raw = f:read('*a')
  f:close()
  return raw
end

local function write_file(path, content)
  local f, err = io.open(path, 'w')
  if not f then return false, err end
  f:write(content)
  f:close()
  return true
end

-- Send command, block (with timeout) until matching result appears.
-- Returns: result_table, nil   on success
--          nil, error_string   on failure / timeout
function M.send(cmd, timeout_secs)
  timeout_secs = timeout_secs or 3.0

  local id = next_id
  next_id = next_id + 1
  cmd.id = id

  local ok, err = write_file(CMD_PATH, json.encode(cmd))
  if not ok then return nil, 'write cmd failed: ' .. tostring(err) end

  local start = hs.timer.secondsSinceEpoch()
  while hs.timer.secondsSinceEpoch() - start < timeout_secs do
    local raw = read_file(RESULT_PATH)
    if raw and #raw > 0 then
      local result = json.decode(raw)
      if result and result.id == id then
        if result.ok then
          return result.result, nil
        else
          return nil, tostring(result.result)
        end
      end
    end
    -- 50ms poll
    hs.timer.usleep(50000)
  end

  return nil, 'timeout after ' .. tostring(timeout_secs) .. 's'
end

function M.ping()
  return M.send({ action = 'ping' }, 1.5)
end

function M.resize_viewport(w, h)
  return M.send({ action = 'resize_viewport', w = w, h = h })
end

function M.get_window_bounds()
  return M.send({ action = 'get_window_bounds' })
end

return M
