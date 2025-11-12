# Hypomnemata Integration with Neovim

## Install

A lazy.nvim example:

```lua
{
  "byrondenham/hypo-nvim",
  dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
  config = function()
    require("hypo").setup({
      vault_path = vim.fn.expand("~/notes/vault"),
    })
  end
}
```

## Commands

- `:HypoInsertLink` (insert `[[id]]`)
- `gf` on `[[id...]]` (goto)
- `gp` on `[[...]]` (preview)
- `:HypoBacklinks` (panel)

Note: make sure `hypo` is installed and your vault is indexed (`hypo reindex`).

### Telescope
- :HypoNotes -> require('hypo.ui.telescope').notes()
- :HypoSearch -> require('hypo.ui.telescope').search()
- :HypoBacklinks -> require('hypo.ui.telescope').backlinks()
- :HypoNeighbours -> require('hypo.ui.telescope').neighbours()

### cmp
Register the source:
```lua
local cmp = require("cmp")
cmp.register_source('hypo', require('hypo.cmp.source').new())
-- Add to your sources list:
-- sources = { { name = 'hypo' }, ... }
```
```
