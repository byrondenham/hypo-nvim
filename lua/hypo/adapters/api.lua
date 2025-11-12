-- adapters/api.lua
-- Minimal HTTP adapter using curl via vim.system. Calls callback(cb) => cb(true, data) or cb(false, err)
local uv = vim.loop
local json = vim.json or vim.fn.json_decode
local config = require('hypo.config')

local M = {}

local function opts_to_query(params)
  if not params then
    return ''
  end
  local parts = {}
  for k, v in pairs(params) do
    if v ~= nil then
      table.insert(parts, vim.fn.escape(k, '') .. '=' .. vim.fn.escape(tostring(v), ''))
    end
  end
  return table.concat(parts, '&')
end

local function request(method, path, params, cb)
  local conf = config().api or {}
  local scheme = conf.https and 'https' or 'http'
  local base = (conf.host or '127.0.0.1') .. ':' .. (conf.port or 8080)
  local url = scheme .. '://' .. base .. path
  if params and next(params) then
    url = url .. '?' .. opts_to_query(params)
  end

  local args = { 'curl', '-sS', '-f', '-X', method, url }
  local headers = {}
  if conf.token and conf.token ~= '' then
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. conf.token)
  end
  -- timeout
  if conf.timeout then
    table.insert(args, '--max-time')
    table.insert(args, tostring(math.ceil(conf.timeout / 1000)))
  end

  -- use vim.system (Neovim >= 0.10) if available
  if vim.system then
    local p = vim.system(args)
    p:call(function(code, signal, stdout, stderr)
      if code ~= 0 then
        cb(false, ('request failed: %s'):format(stderr ~= '' and stderr or tostring(code)))
        return
      end
      local ok, decoded = pcall(vim.json.decode, stdout)
      if not ok then
        cb(false, 'failed to parse JSON from API')
        return
      end
      cb(true, decoded)
    end)
    return
  end

  -- fallback to vim.fn.system
  local res = vim.fn.system(args)
  local code = vim.v.shell_error
  if code ~= 0 then
    cb(false, 'request failed: ' .. tostring(res))
    return
  end
  local ok, decoded = pcall(vim.fn.json_decode, res)
  if not ok then
    cb(false, 'failed to parse JSON from API')
    return
  end
  cb(true, decoded)
end

-- Mapping endpoints ----------------------------------------------------------

function M.list_notes(cb)
  request('GET', '/notes', nil, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    -- Expecting [{id, title}, ...]
    cb(true, res)
  end)
end

function M.search(query, opts, cb)
  opts = opts or {}
  local params = { q = query, limit = opts.limit or 50, snippets = opts.snippets and 1 or 0 }
  request('GET', '/search', params, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    cb(true, res)
  end)
end

function M.backrefs(id, opts, cb)
  local params = { id = id, context = opts and opts.context or 0 }
  request('GET', '/backrefs', params, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    cb(true, res)
  end)
end

function M.yank(ref, opts, cb)
  local params =
    { id = ref.id or ref, anchor = opts and opts.anchor or '', plain = opts and (opts.plain and 1 or 0) or 0 }
  request('GET', '/yank', params, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    cb(true, res)
  end)
end

function M.locate(ref, cb)
  local params = { id = ref.id or ref, anchor = ref.anchor or '' }
  request('GET', '/locate', params, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    cb(true, res)
  end)
end

function M.neighbours(id, depth, cb)
  -- Prefer a /neighbours endpoint; fallback to /graph and compute client-side
  request('GET', '/neighbours', { id = id, depth = depth or 1 }, function(ok, res)
    if ok and res then
      cb(true, res)
      return
    end
    -- fallback
    request('GET', '/graph', nil, function(ok2, graph)
      if not ok2 then
        cb(false, graph)
        return
      end
      -- graph expected: { nodes = { {id,title}, ... }, edges = [ {from,to}, ... ] } or map form
      -- Convert to adjacency and run BFS
      local nodes_map = {}
      local adj = {}
      if graph.nodes then
        for _, n in ipairs(graph.nodes) do
          nodes_map[n.id] = n
          adj[n.id] = adj[n.id] or {}
        end
      end
      if graph.edges then
        for _, e in ipairs(graph.edges) do
          adj[e.from] = adj[e.from] or {}
          adj[e.to] = adj[e.to] or {}
          adj[e.from][e.to] = true
          adj[e.to][e.from] = true
        end
      end
      -- BFS
      local depth_n = depth or 1
      local q = { id }
      local seen = { [id] = 0 }
      local res_nodes = {}
      while #q > 0 do
        local cur = table.remove(q, 1)
        local dcur = seen[cur]
        if dcur < depth_n then
          for nb, _ in pairs(adj[cur] or {}) do
            if not seen[nb] then
              seen[nb] = dcur + 1
              table.insert(q, nb)
            end
          end
        end
      end
      for nid, _ in pairs(seen) do
        if nid ~= id then
          table.insert(res_nodes, { id = nid, title = (nodes_map[nid] and nodes_map[nid].title) or '', degree = 0 })
        end
      end
      cb(true, res_nodes)
    end)
  end)
end

function M.meta_get(id, keys, cb)
  local params = { id = id }
  if keys then
    params.keys = table.concat(keys, ',')
  end
  request('GET', '/notes/' .. vim.fn.escape(id, ''), params, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    -- Expect res.meta or similar
    cb(true, res.meta or res)
  end)
end

function M.meta_set(id, kv, cb)
  -- POST to /notes/:id with body containing kv
  -- For simplicity, use curl -X POST -H "Content-Type: application/json" --data '<json>'
  local conf = config().api or {}
  local scheme = conf.https and 'https' or 'http'
  local base = (conf.host or '127.0.0.1') .. ':' .. (conf.port or 8080)
  local url = scheme .. '://' .. base .. '/notes/' .. id
  local body = vim.fn.json_encode({ meta = kv })
  local args = { 'curl', '-sS', '-f', '-X', 'POST', url, '-H', 'Content-Type: application/json', '-d', body }
  if conf.token and conf.token ~= '' then
    table.insert(args, 1, '-H') -- incorrect ordering safeguard not critical here
    -- simpler: append header
    table.insert(args, '-H')
    table.insert(args, 'Authorization: Bearer ' .. conf.token)
  end

  if vim.system then
    local p = vim.system(args)
    p:call(function(code, signal, stdout, stderr)
      if code ~= 0 then
        cb(false, stderr ~= '' and stderr or 'meta_set failed')
        return
      end
      local ok2, decoded = pcall(vim.json.decode, stdout)
      if not ok2 then
        cb(false, 'failed to parse JSON response')
        return
      end
      cb(true, decoded)
    end)
    return
  end

  local res = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    cb(false, res)
    return
  end
  local ok2, decoded = pcall(vim.fn.json_decode, res)
  if not ok2 then
    cb(false, 'failed to parse JSON response')
    return
  end
  cb(true, decoded)
end

function M.reindex(cb)
  request('POST', '/reindex', nil, function(ok, res)
    if not ok then
      cb(false, res)
      return
    end
    cb(true, res)
  end)
end

return M
