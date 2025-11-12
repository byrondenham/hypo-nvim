-- health.lua
local M = {}
local config = require('hypo.config')

function M.run()
  local health = vim.health or vim.notify and require('vim.health') or nil
  if not health and not vim.health then
    vim.notify('checkhealth unavailable in this version of Neovim', vim.log.levels.WARN)
    return
  end
  -- Use vim.health when available
  if vim.health then
    vim.health.report_start('hypo-nvim')
    local conf = config()
    if conf.backend == 'cli' then
      local exe = vim.fn.executable('hypo') == 1
      if exe then
        vim.health.report_ok('hypo binary found in PATH')
      else
        vim.health.report_error('hypo binary not found in PATH')
      end
    else
      vim.health.report_ok('backend = api; ensure hypo serve is reachable')
      -- Optionally attempt a request (non-blocking)
    end
    local vault = conf.vault_path or ''
    if vault == '' then
      vim.health.report_warn('vault_path not configured')
    else
      if vim.fn.isdirectory(vault) == 1 then
        vim.health.report_ok('vault exists: ' .. vault)
      else
        vim.health.report_error('vault path missing: ' .. vault)
      end
    end
    vim.health.report_ok('health checks completed')
    return
  end
  -- fallback
  vim.notify('Unable to run full checkhealth; use :checkhealth in recent Neovim', vim.log.levels.INFO)
end

return M
