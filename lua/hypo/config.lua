local defaults = {
  backend = {
    type = 'cli',
    watch = {
      mode = 'poll',
      interval_ms = 2000,
      debounce_ms = 250,
    },
  },
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
  lint = {
    auto = false,
    open_quickfix = true,
    max_problems = 500,
    virtual_text_width = 80,
  },
  assets = {
    dir = 'assets',
    slugify = true,
    paste = {
      enable = false,
      provider = 'auto',
    },
  },
  session = {
    per_tab = true,
    recent_limit = 8,
  },
}

local C = vim.deepcopy(defaults)

local M = {}

local function deep_extend(dst, src)
  for k, v in pairs(src) do
    if type(v) == 'table' then
      if type(dst[k]) ~= 'table' then
        dst[k] = {}
      end
      deep_extend(dst[k], v)
    else
      dst[k] = v
    end
  end
end

function M.setup(opts)
  if not opts then
    return
  end
  if opts.backend and type(opts.backend) ~= 'table' then
    opts.backend = { type = opts.backend }
  end
  deep_extend(C, opts)
end

function M.get()
  return C
end

function M.get_backend_type(conf)
  conf = conf or C
  local backend = conf.backend
  if type(backend) == 'table' then
    return backend.type or backend.mode or backend.name or 'cli'
  end
  return backend or 'cli'
end

function M.get_watch_conf(conf)
  conf = conf or C
  if type(conf.backend) == 'table' and conf.backend.watch then
    return conf.backend.watch
  end
  if conf.watch then
    return conf.watch
  end
  return defaults.backend.watch
end

return M
