-- refresh.lua
-- Live refresh daemon that monitors vault changes and invalidates cache
local M = {}
local uv = vim.loop
local config = require('hypo.config')
local memo = require('hypo.cache.memo')

local poll_timer = nil
local subscribe_job = nil
local subscribe_stderr = {}
local last_mtime = nil
local is_running = false
local is_focused = true
local current_mode = nil
local active_watch_conf = nil

-- Flood protection: circular buffer for event timestamps
local event_buffer = {}
local event_buffer_size = 20
local event_buffer_idx = 1
local is_flooding = false
local flood_cooldown_timer = nil

local focus_group = vim.api.nvim_create_augroup('HypoRefreshFocus', { clear = true })

vim.api.nvim_create_autocmd('FocusLost', {
  group = focus_group,
  callback = function()
    is_focused = false
  end,
})

vim.api.nvim_create_autocmd('FocusGained', {
  group = focus_group,
  callback = function()
    is_focused = true
    if is_running and current_mode == 'poll' then
      M.check_now()
    end
  end,
})

-- Get DB mtime for CLI backend
local function get_db_mtime(conf)
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
  vim.schedule(function()
    require('hypo.provider').list_notes(function(ok, notes)
      if ok and notes then
        cb(#notes)
      else
        cb(nil)
      end
    end)
  end)
end

-- Invalidate cache and emit event
local function invalidate()
  memo.clear()
  vim.schedule(function()
    vim.api.nvim_exec_autocmds('User', { pattern = 'HypoRefresh' })
  end)
end

-- Track event and check for flooding
local function track_event()
  local now = uv.now()
  event_buffer[event_buffer_idx] = now
  event_buffer_idx = (event_buffer_idx % event_buffer_size) + 1

  -- Check if we're flooding
  local conf = config.get()
  local flood_conf = (conf.backend and conf.backend.watch and conf.backend.watch.flood) or {}
  local max_batches = flood_conf.max_batches or 8
  local window_ms = flood_conf.window_ms or 800

  -- Count events in window
  local count = 0
  for _, ts in ipairs(event_buffer) do
    if ts and (now - ts) < window_ms then
      count = count + 1
    end
  end

  if count >= max_batches and not is_flooding then
    is_flooding = true
    -- Start cooldown timer
    if flood_cooldown_timer then
      flood_cooldown_timer:stop()
      flood_cooldown_timer:close()
    end
    flood_cooldown_timer = uv.new_timer()
    flood_cooldown_timer:start(2000, 0, function()
      is_flooding = false
      event_buffer = {}
      event_buffer_idx = 1
      if flood_cooldown_timer then
        flood_cooldown_timer:close()
        flood_cooldown_timer = nil
      end
    end)
  end

  return is_flooding
end

local function stop_poll()
  if poll_timer then
    poll_timer:stop()
    poll_timer:close()
    poll_timer = nil
  end
end

local function stop_subscribe()
  if subscribe_job then
    pcall(vim.fn.jobstop, subscribe_job)
    subscribe_job = nil
  end
  subscribe_stderr = {}
end

local function check_for_changes(cb)
  local conf = config.get()
  local backend_type = config.get_backend_type(conf)

  if backend_type == 'cli' then
    local mtime = get_db_mtime(conf)
    if mtime and mtime ~= last_mtime then
      last_mtime = mtime
      cb(true)
      return
    end
    cb(false)
  else
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

local function start_poll(conf, watch_conf)
  stop_poll()
  local backend_type = config.get_backend_type(conf)
  if backend_type == 'cli' then
    last_mtime = get_db_mtime(conf)
  else
    last_mtime = nil
  end

  local interval = watch_conf.interval_ms or 2000
  poll_timer = uv.new_timer()
  poll_timer:start(interval, interval, function()
    if not is_focused then
      return
    end
    check_for_changes(function(changed)
      if changed then
        invalidate()
      end
    end)
  end)
  current_mode = 'poll'
end

local function fallback_to_poll(reason)
  local conf = config.get()
  local watch_conf = active_watch_conf or config.get_watch_conf(conf)
  stop_subscribe()
  start_poll(conf, watch_conf)
  vim.schedule(function()
    vim.notify(reason .. ' – switched to poll mode', vim.log.levels.WARN)
  end)
end

local function start_subscribe(conf, watch_conf)
  stop_subscribe()
  subscribe_stderr = {}
  local backend_type = config.get_backend_type(conf)
  if backend_type ~= 'cli' then
    return false, 'subscribe mode requires CLI backend'
  end

  local cmd = { conf.hypo_cmd or 'hypo', 'watch', '--json' }
  local debounce = watch_conf.debounce_ms or 250
  table.insert(cmd, '--debounce-ms')
  table.insert(cmd, tostring(debounce))
  if conf.vault_path and conf.vault_path ~= '' then
    table.insert(cmd, '--vault')
    table.insert(cmd, conf.vault_path)
  end

  local jobid = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line and line ~= '' then
          local ok, payload = pcall(vim.json.decode, line)
          if ok and payload then
            -- Track event for flood protection
            if not track_event() then
              invalidate()
            end
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line and line ~= '' then
          table.insert(subscribe_stderr, line)
        end
      end
    end,
    on_exit = function(_, code)
      subscribe_job = nil
      if not is_running then
        return
      end
      if code ~= 0 then
        local reason = table.concat(subscribe_stderr, '\n')
        if reason == '' then
          reason = 'hypo watch exited with code ' .. tostring(code)
        else
          reason = 'hypo watch exited with code ' .. tostring(code) .. ': ' .. reason
        end
        fallback_to_poll(reason)
      else
        fallback_to_poll('hypo watch stopped')
      end
    end,
  })

  if jobid <= 0 then
    stop_subscribe()
    return false, 'failed to spawn hypo watch process'
  end

  subscribe_job = jobid
  current_mode = 'subscribe'
  return true
end

function M.touch()
  invalidate()
end

function M.check_now()
  if not is_running then
    return
  end
  check_for_changes(function(changed)
    if changed then
      invalidate()
    end
  end)
end

function M.start()
  if is_running then
    return
  end

  local conf = config.get()
  active_watch_conf = config.get_watch_conf(conf)
  local mode = (active_watch_conf.mode or 'poll'):lower()

  if mode == 'off' then
    return
  end

  if mode == 'subscribe' then
    local ok, err_msg = start_subscribe(conf, active_watch_conf)
    if ok then
      is_running = true
      return
    end
    vim.notify(
      'Failed to start hypo watch subscription: ' .. err_msg .. ' – falling back to poll mode',
      vim.log.levels.WARN
    )
    mode = 'poll'
  end

  start_poll(conf, active_watch_conf)
  is_running = true
end

function M.stop()
  stop_poll()
  stop_subscribe()
  is_running = false
  current_mode = nil
end

function M.status()
  if not is_running then
    return '× offline'
  end

  if current_mode == 'subscribe' then
    return '● watching'
  elseif current_mode == 'poll' then
    return '○ polling'
  end

  return '× offline'
end

return M
