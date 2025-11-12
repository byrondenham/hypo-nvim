-- refresh.lua
-- Live refresh daemon that monitors vault changes and invalidates cache
local M = {}
local uv = vim.loop
local config = require('hypo.config')
local memo = require('hypo.cache.memo')

local timer = nil
local last_mtime = nil
local is_focused = true
local is_running = false

-- Get DB mtime for CLI backend
local function get_db_mtime()
  local conf = config.get()
  local vault = conf.vault_path
  if not vault or vault == '' then
    return nil
  end

  local db_path = conf.db_path or (vault .. '/.hypo/index.sqlite')
  local stat = uv.fs_stat(db_path)
  if stat then
    return stat.mtime.sec * 1000000000 + stat.mtime.nsec
  end
  return nil
end

-- Check API health for changes
local function check_api_health(cb)
  local adapter = require('hypo.adapters.api')
  -- Simple ping to /health or /graph
  vim.schedule(function()
    -- For now, we'll use a simple approach: check if notes count changed
    require('hypo.provider').list_notes(function(ok, notes)
      if ok and notes then
        cb(#notes)
      else
        cb(nil)
      end
    end)
  end)
end

-- Check if vault has changed
local function check_for_changes(cb)
  local conf = config.get()

  if conf.backend == 'cli' then
    local mtime = get_db_mtime()
    if mtime and mtime ~= last_mtime then
      last_mtime = mtime
      cb(true)
      return
    end
    cb(false)
  else
    -- API backend: check health endpoint or notes count
    check_api_health(function(count)
      if count and count ~= last_mtime then
        last_mtime = count
        cb(true)
        return
      end
      cb(false)
    end)
  end
end

-- Invalidate cache and emit event
local function invalidate()
  memo.clear()
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'HypoRefresh' })
  end)
end

-- Manual invalidation
function M.touch()
  invalidate()
end

-- Start the refresh daemon
function M.start()
  if is_running then
    return
  end

  local conf = config.get()
  local watch_conf = conf.backend and conf.backend.watch or {}
  local mode = watch_conf.mode or 'poll'

  if mode == 'off' then
    return
  end

  if mode == 'poll' then
    local interval = watch_conf.interval_ms or 2000

    -- Initialize last_mtime
    if conf.backend == 'cli' then
      last_mtime = get_db_mtime()
    end

    timer = uv.new_timer()
    timer:start(interval, interval, function()
      if not is_focused then
        return
      end

      check_for_changes(function(changed)
        if changed then
          invalidate()
        end
      end)
    end)

    is_running = true

    -- Setup focus tracking
    vim.api.nvim_create_autocmd('FocusLost', {
      group = vim.api.nvim_create_augroup('HypoRefreshFocus', { clear = true }),
      callback = function()
        is_focused = false
      end,
    })

    vim.api.nvim_create_autocmd('FocusGained', {
      group = vim.api.nvim_create_augroup('HypoRefreshFocus', { clear = false }),
      callback = function()
        is_focused = true
        -- Check immediately on focus gain
        check_for_changes(function(changed)
          if changed then
            invalidate()
          end
        end)
      end,
    })
  elseif mode == 'subscribe' then
    -- TODO: Implement watch mode with `hypo watch --json`
    vim.notify('Watch mode "subscribe" not yet implemented, falling back to poll', vim.log.levels.WARN)
    -- Fall back to poll for now
    watch_conf.mode = 'poll'
    M.start()
  end
end

-- Stop the refresh daemon
function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  is_running = false
end

return M
