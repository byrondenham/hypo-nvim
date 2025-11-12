-- features/diag.lua
-- Diagnostics panel showing backend info, cache stats, and recent requests
local M = {}
local config = require('hypo.config')
local provider = require('hypo.provider')
local memo = require('hypo.cache.memo')

local function format_duration(ms)
  if ms < 1000 then
    return string.format('%dms', ms)
  elseif ms < 60000 then
    return string.format('%.1fs', ms / 1000)
  else
    return string.format('%.1fm', ms / 60000)
  end
end

local function get_db_mtime_age()
  local conf = config.get()
  if config.get_backend_type(conf) ~= 'cli' then
    return 'N/A (API backend)'
  end

  local vault = conf.vault_path
  if not vault or vault == '' then
    return 'N/A (no vault_path)'
  end

  local db_path = conf.db_path or (vault .. '/.hypo/index.sqlite')
  local stat = vim.loop.fs_stat(db_path)
  if not stat then
    return 'DB not found'
  end

  local mtime_ns = stat.mtime.sec * 1000000000 + stat.mtime.nsec
  local now_ns = vim.loop.now() * 1000000 -- convert ms to ns
  local age_ms = (now_ns - mtime_ns) / 1000000

  return format_duration(age_ms)
end

local function get_hypo_version(cb)
  local conf = config.get()

  if config.get_backend_type(conf) == 'cli' then
    local cmd = conf.hypo_cmd or 'hypo'
    vim.fn.jobstart({ cmd, '--version' }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data and #data > 0 then
          local version = table.concat(data, ' '):gsub('\n', ' '):gsub('%s+', ' ')
          cb(vim.trim(version))
        else
          cb('unknown')
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          cb('error')
        end
      end,
    })
  else
    -- Try API /health endpoint
    cb('API backend (version check not implemented)')
  end
end

function M.open_panel()
  local conf = config.get()
  local cache_stats = memo.stats()
  local req_stats = provider.stats()

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'hypodiag'

  -- Build content
  local backend_type = config.get_backend_type(conf)
  local lines = {
    '# Hypo Diagnostics',
    '',
    '## Backend Configuration',
    'Mode: ' .. backend_type,
    'Vault: ' .. (conf.vault_path or 'not set'),
  }

  if backend_type == 'cli' then
    table.insert(
      lines,
      'DB Path: ' .. (conf.db_path or (conf.vault_path and (conf.vault_path .. '/.hypo/index.sqlite') or 'N/A'))
    )
  else
    table.insert(lines, 'API Host: ' .. (conf.api.host or '127.0.0.1') .. ':' .. (conf.api.port or 8765))
  end

  table.insert(lines, '')
  table.insert(lines, '## Index Freshness')
  table.insert(lines, 'Last modified: ' .. get_db_mtime_age())

  table.insert(lines, '')
  table.insert(lines, '## Cache Statistics')
  table.insert(lines, 'Entries: ' .. cache_stats.count)
  table.insert(lines, 'Oldest entry: ' .. format_duration(cache_stats.oldest_age_ms))
  table.insert(lines, 'Last clear: ' .. format_duration(cache_stats.last_clear_ms) .. ' ago')

  table.insert(lines, '')
  table.insert(lines, '## Recent Requests (last 10)')
  table.insert(lines, '')

  for i = 1, math.min(10, #req_stats) do
    local stat = req_stats[i]
    local status = stat.ok and 'OK' or 'ERR'
    local line = string.format('  [%s] %s: %dms', status, stat.route, stat.duration_ms)
    table.insert(lines, line)
  end

  table.insert(lines, '')
  table.insert(lines, '## Actions')
  table.insert(lines, '  [r] Reindex vault')
  table.insert(lines, '  [c] Clear cache')
  table.insert(lines, '  [q] Close')

  -- Get version async
  get_hypo_version(function(version)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        local existing_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        -- Insert version after backend section
        table.insert(existing_lines, 6, 'Version: ' .. version)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, existing_lines)
      end
    end)
  end)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Open window
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = conf.ui.border or 'rounded',
    title = ' Hypo Diagnostics ',
    title_pos = 'center',
  })

  -- Set up keymaps
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function do_reindex()
    close()
    vim.notify('Reindexing vault...', vim.log.levels.INFO)
    provider.reindex(function(ok, res)
      if ok then
        vim.notify('Reindex complete', vim.log.levels.INFO)
      else
        vim.notify('Reindex failed: ' .. tostring(res), vim.log.levels.ERROR)
      end
    end)
  end

  local function do_clear_cache()
    memo.clear()
    vim.notify('Cache cleared', vim.log.levels.INFO)
    close()
  end

  vim.keymap.set('n', 'q', close, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'r', do_reindex, { buffer = buf, nowait = true })
  vim.keymap.set('n', 'c', do_clear_cache, { buffer = buf, nowait = true })
end

return M
