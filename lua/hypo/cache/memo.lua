-- cache/memo.lua
local M = {}
local store = {}
local last_clear_time = vim.loop.now()
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
  last_clear_time = now()
end

function M.stats()
  local count = 0
  local oldest_age = 0
  local current_time = now()
  for k, v in pairs(store) do
    count = count + 1
    local age = current_time - v.t
    if age > oldest_age then
      oldest_age = age
    end
  end
  return {
    count = count,
    oldest_age_ms = oldest_age,
    last_clear_ms = current_time - last_clear_time,
  }
end

return M
