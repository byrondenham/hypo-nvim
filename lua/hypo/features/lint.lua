local M = {}

local config = require('hypo.config')
local signs = require('hypo.ui.signs')

local namespace = signs.namespace()
local pending = {}
local running = false
local auto_enabled = false
local auto_group = vim.api.nvim_create_augroup('HypoLintAuto', { clear = true })
local pending_group = vim.api.nvim_create_augroup('HypoLintPending', { clear = true })

local severity_lookup = {
  error = vim.diagnostic.severity.ERROR,
  err = vim.diagnostic.severity.ERROR,
  warning = vim.diagnostic.severity.WARN,
  warn = vim.diagnostic.severity.WARN,
  info = vim.diagnostic.severity.INFO,
  information = vim.diagnostic.severity.INFO,
  hint = vim.diagnostic.severity.HINT,
}

local quickfix_type = {
  [vim.diagnostic.severity.ERROR] = 'E',
  [vim.diagnostic.severity.WARN] = 'W',
  [vim.diagnostic.severity.INFO] = 'I',
  [vim.diagnostic.severity.HINT] = 'I',
}

local function normalize_path(path)
  if not path or path == '' then
    return nil
  end
  return vim.fs.normalize(path)
end

local function buffer_id(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if not name or name == '' then
    return nil
  end
  local id = vim.fn.fnamemodify(name, ':t:r')
  if id == '' then
    return nil
  end
  return id
end

local function buffer_in_vault(bufnr)
  local conf = config.get()
  if not conf.vault_path or conf.vault_path == '' then
    return false
  end
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  if buf_path == '' then
    return false
  end
  buf_path = normalize_path(buf_path)
  local vault = normalize_path(conf.vault_path)
  return buf_path and vault and buf_path:sub(1, #vault) == vault
end

local function id_to_path(id)
  local conf = config.get()
  if not id or id == '' then
    return nil
  end
  if not conf.vault_path or conf.vault_path == '' then
    return nil
  end
  return normalize_path(vim.fs.joinpath(conf.vault_path, id .. '.md'))
end

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
  group = pending_group,
  callback = function(args)
    local name = normalize_path(vim.api.nvim_buf_get_name(args.buf))
    if not name then
      return
    end
    local diags = pending[name]
    if diags then
      vim.diagnostic.set(namespace, args.buf, diags, {})
      pending[name] = nil
    end
  end,
})

local function backend_available(opts)
  local backend_type = config.get_backend_type()
  if backend_type ~= 'cli' then
    if not (opts and opts.silent) then
      vim.notify('hypo.nvim lint is only available for the CLI backend', vim.log.levels.WARN)
    end
    return false
  end
  return true
end

local function parse_results(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout or '[]')
  if not ok or type(decoded) ~= 'table' then
    return nil, 'Failed to parse lint output'
  end
  return decoded
end

local function build_diag(item)
  local severity = severity_lookup[string.lower(item.severity or 'info')] or vim.diagnostic.severity.INFO
  local pos = item.pos or item.position or {}
  local range = item.range or {}
  local start_line = item.line or pos.line or range.start_line or 1
  local start_col = item.col or pos.col or pos.column or range.start_col or range.start_column or 1
  local end_line = item.end_line or range.end_line or start_line
  local end_col = item.end_col or range.end_col or range.end_column or start_col
  local message = vim.trim(item.message or 'Lint issue')

  return {
    lnum = math.max(start_line - 1, 0),
    col = math.max(start_col - 1, 0),
    end_lnum = math.max(end_line - 1, 0),
    end_col = math.max(end_col - 1, 0),
    severity = severity,
    message = message,
    source = 'hypo',
  }
end

local function build_quickfix_entry(path, diag)
  return {
    filename = path,
    lnum = (diag.lnum or 0) + 1,
    col = (diag.col or 0) + 1,
    text = diag.message,
    type = quickfix_type[diag.severity] or 'I',
  }
end

local function run_cli(args, cb)
  local cli = require('hypo.adapters.cli')
  cli.run(args, nil, function(code, stdout, stderr)
    if code ~= 0 then
      cb(false, stderr ~= '' and stderr or stdout)
      return
    end
    cb(true, stdout)
  end)
end

local function filter_results(results, opts)
  if not opts then
    return results
  end
  local filtered = {}
  for _, item in ipairs(results) do
    local keep = true
    if opts.id then
      keep = keep and item.id == opts.id
    end
    if opts.path then
      local resolved = normalize_path(item.path) or id_to_path(item.id)
      keep = keep and resolved == opts.path
    end
    if keep then
      table.insert(filtered, item)
    end
  end
  return filtered
end

local function apply_results(results)
  vim.diagnostic.reset(namespace)
  pending = {}

  local by_buf = {}
  local quickfix = {}
  local conf = config.get()
  local max_problems = (conf.lint and conf.lint.max_problems) or 500
  local count = 0

  for _, item in ipairs(results) do
    if count >= max_problems then
      break
    end
    local path = normalize_path(item.path) or id_to_path(item.id)
    if path then
      local diag = build_diag(item)
      local bufnr = vim.fn.bufnr(path, false)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        by_buf[bufnr] = by_buf[bufnr] or {}
        table.insert(by_buf[bufnr], diag)
      else
        pending[path] = pending[path] or {}
        table.insert(pending[path], diag)
      end
      table.insert(quickfix, build_quickfix_entry(path, diag))
      count = count + 1
    end
  end

  for bufnr, diags in pairs(by_buf) do
    vim.diagnostic.set(namespace, bufnr, diags, {})
  end

  if next(pending) then
    -- Ensure pending diagnostics attach when buffers open
    for path, diags in pairs(pending) do
      local bufnr = vim.fn.bufnr(path, false)
      if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
        vim.diagnostic.set(namespace, bufnr, diags, {})
        pending[path] = nil
      end
    end
  end

  vim.fn.setqflist({}, 'r')
  vim.fn.setqflist(quickfix, 'r')
  local lint_conf = conf.lint or {}
  if #quickfix == 0 then
    if lint_conf.open_quickfix then
      pcall(vim.cmd, 'cclose')
    end
  elseif lint_conf.open_quickfix then
    vim.cmd('cwindow')
  end
end

local function handle_run(opts)
  if not backend_available(opts) then
    return
  end
  if running then
    if not (opts and opts.silent) then
      vim.notify('hypo lint already running', vim.log.levels.INFO)
    end
    return
  end
  running = true

  local args = { 'lint', '--json' }
  run_cli(args, function(ok, stdout_or_err)
    running = false
    if not ok then
      if not (opts and opts.silent) then
        vim.notify('hypo lint failed: ' .. stdout_or_err, vim.log.levels.ERROR)
      end
      return
    end

    local results, err = parse_results(stdout_or_err)
    if not results then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end

    if opts and (opts.id or opts.path) then
      results = filter_results(results, opts)
    end

    apply_results(results)
  end)
end

function M.run()
  handle_run()
end

function M.run_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  if not buffer_in_vault(bufnr) then
    vim.notify('Current buffer is not part of the active vault', vim.log.levels.WARN)
    return
  end
  local id = buffer_id(bufnr)
  if not id then
    vim.notify('Unable to determine current note id', vim.log.levels.WARN)
    return
  end
  handle_run({ id = id, path = normalize_path(vim.api.nvim_buf_get_name(bufnr)) })
end

function M.toggle_watch()
  auto_enabled = not auto_enabled
  if auto_enabled then
    vim.api.nvim_clear_autocmds({ group = auto_group })
    vim.api.nvim_create_autocmd('User', {
      group = auto_group,
      pattern = 'HypoRefresh',
      callback = function()
        handle_run({ silent = true })
      end,
    })
    vim.api.nvim_create_autocmd('BufWritePost', {
      group = auto_group,
      callback = function(args)
        if not buffer_in_vault(args.buf) then
          return
        end
        local id = buffer_id(args.buf)
        if not id then
          return
        end
        handle_run({ id = id, path = normalize_path(vim.api.nvim_buf_get_name(args.buf)), silent = true })
      end,
    })
    vim.notify('Hypo lint on change enabled', vim.log.levels.INFO)
  else
    vim.api.nvim_clear_autocmds({ group = auto_group })
    vim.notify('Hypo lint on change disabled', vim.log.levels.INFO)
  end
end

return M
