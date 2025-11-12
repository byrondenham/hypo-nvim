-- features/normalise.lua
local M = {}
local provider = require('hypo.provider')

function M.current()
  local id = require('hypo.util.link').current_id()
  if not id then
    vim.notify('No current note id', vim.log.levels.WARN)
    return
  end
  -- Run reindex or adapter-provided normalise
  provider.reindex(function(ok, res)
    if ok then
      vim.notify('Normalise: done', vim.log.levels.INFO)
    else
      vim.notify('Normalise failed: ' .. tostring(res), vim.log.levels.ERROR)
    end
  end)
end

function M.vault()
  if vim.fn.confirm('Normalise entire vault? This may be slow.', '&Yes\n&No') ~= 1 then
    return
  end
  provider.reindex(function(ok, res)
    if ok then
      vim.notify('Vault normalization: done', vim.log.levels.INFO)
    else
      vim.notify('Vault normalization failed: ' .. tostring(res), vim.log.levels.ERROR)
    end
  end)
end

return M
