-- provider.lua
-- Facade selecting adapters.cli or adapters.api based on config().backend
local M = {}
local config = require('hypo.config')
local memo = require('hypo.cache.memo')

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

local function wrap(cb, key, ttl, fn)
  -- caching wrapper: check memo then call underlying fn
  return function(...)
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
        cb(true, cached)
        return
      end
    end
    -- call actual function
    fn(table.unpack(args), function(ok, res)
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
  local ttl = (config().cache and config().cache.notes_ttl) or 5000
  local f = function(cb2)
    adapter.list_notes(function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(cb, 'list_notes', ttl, f)()
end

function M.search(query, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local ttl = (config().cache and config().cache.search_ttl) or 2000
  local f = function(q, o, cb2)
    adapter.search(q, o, function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(function(ok, res)
    cb(ok, res)
  end, 'search', ttl, f)(query, opts)
end

function M.backrefs(id, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.backrefs(id, opts or {}, cb)
end

function M.yank(ref, opts, cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.yank(ref, opts or {}, function(ok, res)
    -- mutations may require invalidation — caller should do it if needed
    cb(ok, res)
  end)
end

function M.locate(ref, cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.locate(ref, cb)
end

function M.neighbours(id, depth, cb)
  if not adapter then
    cb(false, err)
    return
  end
  local ttl = (config().cache and config().cache.neighbours_ttl) or 5000
  local f = function(i, d, cb2)
    adapter.neighbours(i, d, function(ok, res)
      cb2(ok, res)
    end)
  end
  wrap(cb, 'neighbours', ttl, f)(id, depth)
end

function M.meta_get(id, keys, cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.meta_get(id, keys, cb)
end

function M.meta_set(id, kv, cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.meta_set(id, kv, function(ok, res)
    if ok then
      -- invalidate relevant caches
      memo.del('list_notes')
      memo.clear() -- conservative; you can target keys more precisely
    end
    cb(ok, res)
  end)
end

function M.reindex(cb)
  if not adapter then
    cb(false, err)
    return
  end
  adapter.reindex(function(ok, res)
    if ok then
      memo.clear()
    end
    cb(ok, res)
  end)
end

function M.invalidate_all()
  memo.clear()
end

return M
