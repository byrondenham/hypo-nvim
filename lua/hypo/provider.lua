-- provider.lua
-- Facade selecting adapters.cli or adapters.api based on config().backend
local M = {}
local config = require('hypo.config')
local memo = require('hypo.cache.memo')

-- Telemetry: circular buffer for request stats
local stats_buffer = {}
local stats_max_size = 50
local stats_index = 1

local function record_stat(route, duration_ms, ok)
  stats_buffer[stats_index] = {
    route = route,
    duration_ms = duration_ms,
    ok = ok,
    timestamp = vim.loop.now(),
  }
  stats_index = (stats_index % stats_max_size) + 1
end

function M.stats()
  local result = {}
  for i = 1, stats_max_size do
    if stats_buffer[i] then
      table.insert(result, stats_buffer[i])
    end
  end
  -- Sort by timestamp descending
  table.sort(result, function(a, b)
    return a.timestamp > b.timestamp
  end)
  return result
end

local function choose_adapter()
  local conf = config()
  if conf and conf.backend == 'api' then
    local ok, api = pcall(require, 'hypo.adapters.api')
    if ok then
      return api
    end
  end
  -- fallback to CLI adapter
  local ok2, cli = pcall(require, 'hypo.adapters.cli')
  if ok2 then
    return cli
  end
  return nil, 'no adapter available'
end

local function wrap(cb, key, ttl, fn, route_name)
  -- caching wrapper: check memo then call underlying fn
  return function(...)
    local start_time = vim.loop.now()
    local args = { ... }
    local cache_key = nil
    if key then
      -- build cache key from key + args[1] if present (e.g., query or id)
      local kparts = { key }
      if args[1] then
        table.insert(kparts, tostring(args[1]))
      end
      if args[2] then
        table.insert(kparts, tostring(args[2]))
      end
      cache_key = table.concat(kparts, '::')
      local cached = memo.get(cache_key, ttl)
      if cached ~= nil then
        -- immediate callback with cached value
        local duration = vim.loop.now() - start_time
        record_stat(route_name or key, duration, true)
        cb(true, cached)
        return
      end
    end
    -- call actual function
    fn(table.unpack(args), function(ok, res)
      local duration = vim.loop.now() - start_time
      record_stat(route_name or key, duration, ok)
      if ok and cache_key then
        memo.set(cache_key, res)
      end
      cb(ok, res)
    end)
  end
end

local adapter, err = choose_adapter()

-- Exposed API -----------------------------------------------------------------
-- Each function follows cb(err_bool, data_or_errstr)

function M.list_notes(cb)
  if not adapter then
    cb(false, err)
    return
  end
  -- cached for ~5000ms
  local conf = config.get()
  local ttl = (conf.cache_ttl and conf.cache_ttl.notes) or 5000
  local f = function(cb2)
    adapter.list_notes(function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(cb, 'list_notes', ttl, f, 'list_notes')()
end

function M.search(query, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local conf = config.get()
  local ttl = (conf.cache_ttl and conf.cache_ttl.search) or 2000
  local f = function(q, o, cb2)
    adapter.search(q, o, function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(function(ok, res)
    cb(ok, res)
  end, 'search', ttl, f, 'search')(query, opts)
end

function M.backrefs(id, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.backrefs(id, opts or {}, function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('backrefs', duration, ok)
    cb(ok, res)
  end)
end

function M.yank(ref, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.yank(ref, opts or {}, function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('yank', duration, ok)
    -- mutations may require invalidation — caller should do it if needed
    cb(ok, res)
  end)
end

function M.locate(ref, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.locate(ref, function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('locate', duration, ok)
    cb(ok, res)
  end)
end

function M.neighbours(id, depth, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local conf = config.get()
  local ttl = (conf.cache_ttl and conf.cache_ttl.neighbours) or 5000
  local f = function(i, d, cb2)
    adapter.neighbours(i, d, function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(cb, 'neighbours', ttl, f, 'neighbours')(id, depth)
end

function M.meta_get(id, keys, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.meta_get(id, keys, function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('meta_get', duration, ok)
    cb(ok, res)
  end)
end

function M.meta_set(id, kv, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.meta_set(id, kv, function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('meta_set', duration, ok)
    if ok then
      -- invalidate relevant caches
      memo.del('list_notes')
      memo.clear() -- conservative; you can target keys more precisely
      -- Trigger refresh
      require('hypo.refresh').touch()
    end
    cb(ok, res)
  end)
end

function M.reindex(cb)
  if not adapter then
    cb(false, err)
    return
  end
  local start_time = vim.loop.now()
  adapter.reindex(function(ok, res)
    local duration = vim.loop.now() - start_time
    record_stat('reindex', duration, ok)
    if ok then
      memo.clear()
      -- Trigger refresh
      require('hypo.refresh').touch()
    end
    cb(ok, res)
  end)
end

function M.invalidate_all()
  memo.clear()
end

return M
