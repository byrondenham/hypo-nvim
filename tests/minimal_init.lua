local root = vim.fn.fnamemodify('.', ':p')
vim.opt.runtimepath:append(root)
local cache = vim.fn.stdpath('cache')
local vault = vim.fs.joinpath(cache, 'hypo-test-vault')
vim.fn.mkdir(vault, 'p')
require('hypo').setup({
  vault_path = vault,
  backend = { type = 'cli', watch = { mode = 'off' } },
  lint = { auto = false, open_quickfix = false },
})
