local cli = require('hypo.adapters.cli')
local L = require('hypo.util.link')
local float = require('hypo.ui.float')
local M = {}

function M.preview_under_cursor()
  local ref = L.under_cursor()
  if not ref then
    vim.notify('Hypo: no [[link]]', vim.log.levels.INFO)
    return
  end
  local target = ref.id
  if ref.anchor_kind and ref.anchor_value then
    target = target .. '#' .. (ref.anchor_kind == 'block' and '^' or '') .. ref.anchor_value
  end
  cli.run({ 'yank', target, '--context', '0' }, nil, function(code, out, err)
    if code ~= 0 then
      vim.notify('Hypo yank failed: ' .. (err or out), vim.log.levels.ERROR)
      return
    end
    local lines = {}
    for s in out:gmatch('[^\r\n]+') do
      lines[#lines + 1] = s
    end
    if #lines == 0 then
      lines = { '(empty)' }
    end
    float.show(lines)
  end)
end

return M
