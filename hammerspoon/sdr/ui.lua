-- ui.lua — hs.webview + localhost hs.httpserver JS↔Lua bridge.
--
-- HTTP bridge avoids the WebKit "unsupported URL scheme" error noise that
-- custom URL schemes (sdr://) produce — WebKit raises NSURLErrorDomain -1002
-- before our policyCallback ever runs.
local json = require('hs.json')

local M = {}

local view = nil
local server = nil
local server_port = nil
local handlers = {}

-- Async push queue: events Lua wants to send to JS via long-poll.
local push_queue = {}
local push_waiters = {} -- {response_fn, ...}

function M.register(name, fn)
  handlers[name] = fn
end

-- Encode any Lua value as JSON, fallback to tostring.
local function safe_json(v)
  local ok, out = pcall(json.encode, v)
  if ok then return out end
  return json.encode({ error = tostring(v) })
end

local function url_decode(s)
  return s:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
end

-- HTTP request handler. Routes:
--   POST /call/<handler>  body=<json>          → handler result as JSON
--   GET  /push                                 → drain push queue (long-poll style)
--   GET  /                                     → index.html (port injected)
--   GET  /static/<file>                        → ui/<file>
--
-- We use POST for /call because hs.httpserver's setCallback strips query
-- strings from the path argument, leaving us no way to read GET params.
local function http_handler(method, path, headers, body)
  local route = path

  if route == '/' or route == '/index.html' then
    local repo_root = M._repo_root
    if not repo_root then return 'no repo', 500, {} end
    local f = io.open(repo_root .. '/ui/index.html', 'r')
    if not f then return 'index missing', 500, {} end
    local html = f:read('*a'); f:close()
    html = html:gsub('</head>',
      string.format('<script>window.SDR_PORT=%d;</script></head>', server_port))
    return html, 200, { ['Content-Type'] = 'text/html; charset=utf-8' }
  end

  if route:match('^/static/') then
    local rel = route:sub(9)
    local repo_root = M._repo_root
    local fp = repo_root .. '/ui/' .. rel
    local f = io.open(fp, 'r')
    if not f then return 'not found', 404, {} end
    local content = f:read('*a'); f:close()
    local ctype = 'text/plain'
    if rel:match('%.css$') then ctype = 'text/css'
    elseif rel:match('%.js$')  then ctype = 'text/javascript'
    elseif rel:match('%.png$') then ctype = 'image/png' end
    return content, 200, { ['Content-Type'] = ctype }
  end

  local handler_name = route:match('^/call/(.+)$')
  if handler_name then
    local payload = {}
    if body and #body > 0 then
      local ok, decoded = pcall(json.decode, body)
      if ok and type(decoded) == 'table' then payload = decoded end
    end
    local fn = handlers[handler_name]
    if not fn then
      return safe_json({ ok = false, result = 'unknown handler ' .. handler_name }), 200,
             { ['Content-Type'] = 'application/json' }
    end
    local ok, result = pcall(fn, payload)
    return safe_json({ ok = ok, result = result }), 200,
           { ['Content-Type'] = 'application/json' }
  end

  if route == '/push' then
    local items = push_queue
    push_queue = {}
    return safe_json({ events = items }), 200,
           { ['Content-Type'] = 'application/json' }
  end

  return 'not found', 404, {}
end

function M.push(event_name, data)
  table.insert(push_queue, { name = event_name, data = data or {} })
end

function M.start(repo_root)
  M._repo_root = repo_root
  if server then return server_port end

  server = hs.httpserver.new(false, false)
  server:setInterface('127.0.0.1')
  server:setPort(0) -- pick free port
  server:setCallback(http_handler)
  server:start()
  server_port = server:getPort()
  hs.printf('SDR HTTP bridge on http://127.0.0.1:%d', server_port)
  return server_port
end

function M.open(repo_root)
  if not server then M.start(repo_root) end
  if view then view:show(); view:bringToFront(true); return view end

  local rect = hs.geometry.rect(120, 120, 980, 760)
  view = hs.webview.new(rect)
    :windowTitle('SketchUp Demo Recorder')
    :windowStyle({ 'titled', 'closable', 'miniaturizable', 'resizable' })
    :allowTextEntry(true)
    :allowNewWindows(false)
    :shadow(true)
    :url(string.format('http://127.0.0.1:%d/', server_port))
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
