local cli = require('hypo.adapters.cli')
local M = {}

local function current_id()
  local name = vim.api.nvim_buf_get_name(0)
  return name:match('([a-f0-9]+)%.md$')
end

function M.open_panel()
  local id = current_id()
  if not id then
    vim.notify('Hypo: buffer not an ID-named note', vim.log.levels.INFO)
    return
  end
  cli.run({ 'backrefs', id, '--context', '2' }, nil, function(code, out, err)
    if code ~= 0 then
      vim.notify('Hypo backrefs failed: ' .. (err or out), vim.log.levels.ERROR)
      return
    end
    vim.cmd('vnew')
    local b = vim.api.nvim_get_current_buf()
    vim.bo[b].buftype = 'nofile'
    vim.bo[b].bufhidden = 'wipe'
    vim.bo[b].swapfile = false
    local lines = {}
    for s in out:gmatch('[^\r\n]+') do
      lines[#lines + 1] = s
    end
    if #lines == 0 then
      lines = { '(no backlinks)' }
    end
    vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
    vim.bo[b].modifiable = false
    vim.bo[b].filetype = 'hypo_backlinks'
  end)
end

return M
