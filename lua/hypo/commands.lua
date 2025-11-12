local M = {}
function M.register()
  vim.api.nvim_create_user_command('HypoGoto', function()
    require('hypo.features.goto').goto_under_cursor()
  end, {})
  vim.api.nvim_create_user_command('HypoPreview', function()
    require('hypo.features.preview').preview_under_cursor()
  end, {})
  vim.api.nvim_create_user_command('HypoInsertLink', function()
    require('hypo.features.completion').insert_link()
  end, {})
  vim.api.nvim_create_user_command('HypoBacklinks', function()
    require('hypo.features.backlinks').open_panel()
  end, {})

  -- Telescope commands
  vim.api.nvim_create_user_command('HypoNotes', function()
    require('hypo.ui.telescope').notes()
  end, {})
  vim.api.nvim_create_user_command('HypoSearch', function(opts)
    require('hypo.ui.telescope').search(opts.args ~= '' and opts.args or nil)
  end, { nargs = '?' })
  vim.api.nvim_create_user_command('HypoBacklinksPicker', function()
    require('hypo.ui.telescope').backlinks()
  end, {})
  vim.api.nvim_create_user_command('HypoNeighbors', function()
    require('hypo.ui.telescope').neighbours(nil, 1)
  end, {})
  vim.api.nvim_create_user_command('HypoNeighbors2', function()
    require('hypo.ui.telescope').neighbours(nil, 2)
  end, {})

  -- Diagnostics command
  vim.api.nvim_create_user_command('HypoDiag', function()
    require('hypo.features.diag').open_panel()
  end, {})

  -- suggested defaults; let users override
  vim.keymap.set('n', 'gf', '<cmd>HypoGoto<cr>', { desc = 'Hypo goto link' })
  vim.keymap.set('n', 'gp', '<cmd>HypoPreview<cr>', { desc = 'Hypo preview link' })
  vim.keymap.set('i', '<C-l>', '<cmd>HypoInsertLink<cr>', { desc = 'Hypo insert [[id]]' })
  vim.keymap.set('n', '<leader>hb', '<cmd>HypoBacklinks<cr>', { desc = 'Hypo backlinks' })
end

return M
