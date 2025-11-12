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

