-- health.lua
local M = {}
local config = require('hypo.config')

local function check_backend()
  local conf = config.get()
  if conf.backend == 'cli' then
    local exe = vim.fn.executable(conf.hypo_cmd or 'hypo') == 1
    if exe then
      vim.health.ok('hypo binary found in PATH')
      -- Check version
      local handle = io.popen((conf.hypo_cmd or 'hypo') .. ' --version 2>&1')
      if handle then
        local version = handle:read('*a')
        handle:close()
        if version and version ~= '' then
          vim.health.info('Version: ' .. vim.trim(version))
        end
      end
    else
      vim.health.error('hypo binary not found in PATH')
    end
  else
    vim.health.ok('Backend: API mode')
    vim.health.info('Host: ' .. (conf.api.host or '127.0.0.1') .. ':' .. (conf.api.port or 8765))
  end
end

local function check_vault()
  local conf = config.get()
  local vault = conf.vault_path or ''
  if vault == '' then
    vim.health.warn('vault_path not configured')
  else
    if vim.fn.isdirectory(vault) == 1 then
      vim.health.ok('Vault exists: ' .. vault)

      -- Check DB for CLI backend
      if conf.backend == 'cli' then
        local db_path = conf.db_path or (vault .. '/.hypo/index.sqlite')
        if vim.fn.filereadable(db_path) == 1 then
          vim.health.ok('Database found: ' .. db_path)

          -- Check DB age
          local stat = vim.loop.fs_stat(db_path)
          if stat then
            local age_sec = (vim.loop.now() / 1000) - stat.mtime.sec
            if age_sec < 300 then -- 5 minutes
              vim.health.ok('Index is fresh (< 5 minutes old)')
            elseif age_sec < 3600 then -- 1 hour
              vim.health.info('Index is ' .. math.floor(age_sec / 60) .. ' minutes old')
            else
              vim.health.warn('Index is stale (> 1 hour old), consider running :HypoDiag and reindexing')
            end
          end
        else
          vim.health.warn('Database not found, run: hypo reindex')
        end
      end
    else
      vim.health.error('Vault path does not exist: ' .. vault)
    end
  end
end

local function check_cache()
  local memo = require('hypo.cache.memo')
  local stats = memo.stats()
  vim.health.info('Cache entries: ' .. stats.count)
  if stats.count > 0 then
    vim.health.info('Oldest entry age: ' .. math.floor(stats.oldest_age_ms / 1000) .. 's')
  end
end

local function check_telescope()
  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    vim.health.ok('Telescope is available')
  else
    vim.health.warn('Telescope not installed (pickers will not work)')
  end
end

local function check_cmp()
  local has_cmp = pcall(require, 'cmp')
  if has_cmp then
    vim.health.ok('nvim-cmp is available')
  else
    vim.health.info('nvim-cmp not installed (completion source will not work)')
  end
end

function M.check()
  vim.health.start('hypo-nvim Configuration')
  check_backend()
  check_vault()

  vim.health.start('hypo-nvim Cache')
  check_cache()

  vim.health.start('hypo-nvim Dependencies')
  check_telescope()
  check_cmp()

  vim.health.start('hypo-nvim Commands')
  vim.health.ok('Use :HypoDiag for detailed diagnostics')
end

-- Backward compatibility
M.run = M.check

return M
