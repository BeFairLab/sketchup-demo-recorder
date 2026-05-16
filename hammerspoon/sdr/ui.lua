-- ui.lua — hs.webview wrapper + JS↔Lua bridge.
--
-- The webview loads ui/index.html (resolved relative to repo root) and
-- communicates via window.location = 'sdr://...' messages. We intercept those
-- via a navigation callback and dispatch to Lua handlers.
local json = require('hs.json')

local M = {}

local view = nil
local html_url = nil

-- Registered handlers: { handler_name = function(payload) ... return result end }
local handlers = {}

function M.register(name, fn)
  handlers[name] = fn
end

local function url_decode(s)
  return s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
end

local function handle_navigation(action, webview, navID, url)
  if not url or not url:find('^sdr://') then return false end
  local rest = url:sub(7) -- strip "sdr://"
  -- Format: "sdr://<handler>?<jsonpayload-urlencoded>"
  local handler_name, payload_str = rest:match('^([^?]+)%??(.*)$')
  if not handler_name then return true end
  local payload = {}
  if payload_str and #payload_str > 0 then
    local ok, decoded = pcall(json.decode, url_decode(payload_str))
    if ok and type(decoded) == 'table' then payload = decoded end
  end
  local fn = handlers[handler_name]
  if not fn then
    hs.printf('sdr ui: unknown handler %s', handler_name)
    return true
  end
  local ok, result = pcall(fn, payload)
  if not ok then
    hs.printf('sdr ui handler error %s: %s', handler_name, tostring(result))
  end
  -- Push result back to JS as window.SDR_BRIDGE_RESPONSE(<reqid>, <json>)
  if payload.reqid then
    local enc = json.encode({ ok = ok, result = result })
    -- Escape for JS string literal
    local esc = enc:gsub('\\', '\\\\'):gsub("'", "\\'")
    webview:evaluateJavaScript(string.format(
      "window.SDR_BRIDGE_RESPONSE && window.SDR_BRIDGE_RESPONSE(%q, '%s')",
      tostring(payload.reqid), esc))
  end
  return true -- don't actually navigate
end

function M.push(event_name, data)
  if not view then return end
  local enc = json.encode(data or {})
  local esc = enc:gsub('\\', '\\\\'):gsub("'", "\\'")
  view:evaluateJavaScript(string.format(
    "window.SDR_PUSH && window.SDR_PUSH(%q, '%s')",
    event_name, esc))
end

function M.open(repo_root)
  if view then view:show(); view:bringToFront(true); return view end

  html_url = 'file://' .. repo_root .. '/ui/index.html'

  local rect = hs.geometry.rect(120, 120, 980, 760)
  view = hs.webview.new(rect)
    :windowTitle('SketchUp Demo Recorder')
    :windowStyle({ 'titled', 'closable', 'miniaturizable', 'resizable' })
    :allowTextEntry(true)
    :allowNewWindows(false)
    :navigationCallback(handle_navigation)
    :url(html_url)
    :show()
    :bringToFront(true)

  return view
end

function M.close()
  if view then view:delete(); view = nil end
end

function M.is_open()
  return view ~= nil
end

return M
