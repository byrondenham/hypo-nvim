local C = {
  backend = 'cli',
  hypo_cmd = 'hypo',
  vault_path = nil,
  db_path = nil,
  api = { host = '127.0.0.1', port = 8765, token = nil, https = false, timeout = 3000 },
  ui = { border = 'rounded', max_width = 84, max_height = 22 },
  debounce = { preview = 80, search = 120 },
  telescope = { enable = true },
  cmp = { enable = true, max_items = 200, include_aliases = true },
  cache_ttl = { notes = 5000, search = 2000, neighbours = 5000 },
  timeouts = { request_ms = 3000 },
  watch = { mode = 'poll', interval_ms = 2000 },
}
local M = {}
function M.setup(opts)
  for k, v in pairs(opts or {}) do
    if type(v) == 'table' and type(C[k]) == 'table' then
      for kk, vv in pairs(v) do
        C[k][kk] = vv
      end
    else
      C[k] = v
    end
  end
end
function M.get()
  return C
end
return M
