local M = {}

local config = require('hypo.config')
local memo = require('hypo.cache.memo')

local state = {
  current = nil,
  per_tab = {},
  recent = {},
  global = nil,
}

local session_group = vim.api.nvim_create_augroup('HypoSession', { clear = true })
local cache_file = vim.fs.normalize(vim.fn.stdpath('cache') .. '/hypo_recent_vaults.json')

local function session_config()
  return config.get().session or {}
end

local function save_recent()
  local dir = vim.fs.dirname(cache_file)
  if dir and dir ~= '' then
    vim.fn.mkdir(dir, 'p')
  end
  pcall(vim.fn.writefile, { vim.json.encode(state.recent) }, cache_file)
end

local function load_recent()
  if vim.fn.filereadable(cache_file) ~= 1 then
    return
  end
  local ok, data = pcall(vim.fn.readfile, cache_file)
  if not ok then
    return
  end
  local ok_json, parsed = pcall(vim.json.decode, table.concat(data, '\n'))
  if ok_json and type(parsed) == 'table' then
    state.recent = parsed
  end
end

local function push_recent(path)
  for i = #state.recent, 1, -1 do
    if state.recent[i] == path then
      table.remove(state.recent, i)
    end
  end
  table.insert(state.recent, 1, path)
  local limit = session_config().recent_limit or 8
  while #state.recent > limit do
    table.remove(state.recent)
  end
  save_recent()
end

local function apply_vault(path)
  if not path or path == '' then
    return
  end
  config.setup({ vault_path = path })
  state.current = path
  state.global = path
  require('hypo.provider').reload()
  memo.clear()
  require('hypo.refresh').stop()
  require('hypo.refresh').start()
  vim.api.nvim_exec_autocmds('User', { pattern = 'HypoRefresh' })
  vim.notify('Switched to vault: ' .. path, vim.log.levels.INFO)
end

local function tab_key(tabpage)
  return vim.api.nvim_tabpage_get_number(tabpage)
end

local function apply_for_tab(tabnr)
  local per_tab = session_config().per_tab
  if per_tab == nil then
    per_tab = true
  end
  local desired = per_tab and state.per_tab[tabnr] or state.global
  if desired and desired ~= state.current then
    apply_vault(desired)
  end
end

function M.setup()
  load_recent()
  state.current = config.get().vault_path
  state.global = state.current

  vim.api.nvim_create_autocmd('TabEnter', {
    group = session_group,
    callback = function()
      local tabnr = tab_key(vim.api.nvim_get_current_tabpage())
      apply_for_tab(tabnr)
    end,
  })

  vim.api.nvim_create_autocmd('TabClosed', {
    group = session_group,
    callback = function(args)
      local closed = tonumber(args.file)
      if closed then
        state.per_tab[closed] = nil
      end
    end,
  })
end

local function resolve_path(path)
  if not path or path == '' then
    path = vim.fn.input('Vault path: ', '', 'dir')
  end
  if not path or path == '' then
    return nil
  end
  path = vim.fs.normalize(vim.fn.expand(path))
  return path
end

function M.use(path)
  path = resolve_path(path)
  if not path then
    return
  end
  if vim.fn.isdirectory(path) ~= 1 then
    vim.notify('Vault path does not exist: ' .. path, vim.log.levels.ERROR)
    return
  end
  push_recent(path)
  local per_tab = session_config().per_tab
  if per_tab == nil then
    per_tab = true
  end
  if per_tab then
    local tabnr = tab_key(vim.api.nvim_get_current_tabpage())
    state.per_tab[tabnr] = path
  end
  apply_vault(path)
end

function M.show()
  if state.current and state.current ~= '' then
    vim.notify('Active hypo vault: ' .. state.current, vim.log.levels.INFO)
  else
    vim.notify('No active hypo vault', vim.log.levels.INFO)
  end
end

function M.recent()
  if #state.recent == 0 then
    vim.notify('No recent vaults recorded', vim.log.levels.INFO)
    return
  end
  vim.ui.select(state.recent, { prompt = 'Recent hypo vaults' }, function(choice)
    if choice then
      M.use(choice)
    end
  end)
end

function M.status()
  if not state.current or state.current == '' then
    return '[hypo: none]'
  end
  return string.format('[hypo: %s]', vim.fn.fnamemodify(state.current, ':t'))
end

return M
