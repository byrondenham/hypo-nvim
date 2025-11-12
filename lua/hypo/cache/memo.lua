-- cache/memo.lua
local M = {}
local store = {}
local function now()
  return vim.loop.now()
end

function M.get(key, ttl_ms)
  local e = store[key]
  if not e then
    return nil
  end
  if ttl_ms and (now() - e.t) > ttl_ms then
    store[key] = nil
    return nil
  end
  return e.value
end

function M.set(key, value)
  store[key] = { value = value, t = now() }
end
function M.del(key)
  store[key] = nil
end
function M.clear()
  store = {}
end

return M
