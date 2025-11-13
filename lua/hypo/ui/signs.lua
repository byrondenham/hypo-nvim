local M = {}

local ns = vim.api.nvim_create_namespace('hypo.nvim.lint')
local configured = false

local severity_defs = {
  error = { sign = '󰅚', hl = 'HypoError' },
  warn = { sign = '', hl = 'HypoWarn' },
  info = { sign = '', hl = 'HypoInfo' },
  hint = { sign = '󰌵', hl = 'HypoHint' },
}

local severity_map = {
  [vim.diagnostic.severity.ERROR] = 'HypoErrorSign',
  [vim.diagnostic.severity.WARN] = 'HypoWarnSign',
  [vim.diagnostic.severity.INFO] = 'HypoInfoSign',
  [vim.diagnostic.severity.HINT] = 'HypoHintSign',
}

function M.namespace()
  return ns
end

local function ensure_highlights()
  local links = {
    HypoError = 'DiagnosticError',
    HypoWarn = 'DiagnosticWarn',
    HypoInfo = 'DiagnosticInfo',
    HypoHint = 'DiagnosticHint',
  }

  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

function M.setup()
  if configured then
    return
  end
  ensure_highlights()

  for kind, def in pairs(severity_defs) do
    local sign_name = 'Hypo' .. kind:sub(1, 1):upper() .. kind:sub(2) .. 'Sign'
    if not severity_map[vim.diagnostic.severity[kind:upper()]] then
      severity_map[vim.diagnostic.severity[kind:upper()]] = sign_name
    end
    vim.fn.sign_define(sign_name, { text = def.sign, texthl = def.hl, numhl = def.hl })
  end

  local config_module = require('hypo.config')
  vim.diagnostic.config({
    virtual_text = {
      spacing = 1,
      prefix = '●',
      format = function(diagnostic)
        local width = (config_module.get().lint and config_module.get().lint.virtual_text_width) or 80
        local message = diagnostic.message or ''
        if vim.fn.strdisplaywidth(message) > width then
          message = vim.fn.strcharpart(message, 0, width - 1) .. '…'
        end
        return message
      end,
    },
  }, ns)

  configured = true
end

function M.sign_for(severity)
  return severity_map[severity]
end

function M.statusline_component()
  local refresh = require('hypo.refresh')
  return refresh.status()
end

return M
