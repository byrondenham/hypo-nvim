local C = require('hypo.config').get
local M = {}
local win, buf

function M.show(lines)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local cfg = C().ui
  local width = math.min(cfg.max_width, math.floor(vim.o.columns * 0.8))
  local height = math.min(cfg.max_height, math.floor(vim.o.lines * 0.6))
  win = vim.api.nvim_open_win(buf, false, {
    relative = 'cursor',
    row = 1,
    col = 1,
    width = width,
    height = height,
    style = 'minimal',
    border = cfg.border,
  })
end

return M
