# Hypomnemata Integration with Neovim

A Neovim plugin for working with [Hypomnemata](https://github.com/cablehead/hypo) knowledge bases, providing fast navigation, completion, and search capabilities.

## Features

- 🔗 **Link Navigation**: Jump to notes with `gf` on `[[id]]` links
- 🔍 **Full-Text Search**: Search across your vault with highlighted snippets
- 📝 **Smart Completion**: Auto-complete note IDs with `[[` in markdown files
- 🔄 **Live Refresh**: Automatic cache invalidation when your vault changes
- 📊 **Diagnostics**: Built-in health checks and diagnostics panel
- 🔭 **Telescope Integration**: Rich pickers for notes, search, backlinks, and neighbors
- ⚡ **Performance**: Cached requests with configurable TTLs and timeouts

## Install

### lazy.nvim

```lua
{
  "byrondenham/hypo-nvim",
  dependencies = { 
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",  -- optional, for pickers
    "hrsh7th/nvim-cmp",               -- optional, for completion
  },
  config = function()
    require("hypo").setup({
      vault_path = vim.fn.expand("~/notes/vault"),
      -- Optional: use API backend instead of CLI
      -- backend = "api",
      -- api = {
      --   host = "127.0.0.1",
      --   port = 8765,
      --   token = os.getenv("HYPO_TOKEN"),
      -- },
    })
  end
}
```

**Prerequisites**: Install [hypo](https://github.com/cablehead/hypo) CLI and index your vault:
```bash
hypo reindex --vault ~/notes/vault
```

## Commands

### Basic Navigation
- `:HypoGoto` or `gf` - Jump to note under cursor (on `[[id]]` link)
- `:HypoPreview` or `gp` - Preview note in floating window
- `:HypoInsertLink` or `<C-l>` (insert mode) - Insert a note link
- `:HypoBacklinks` - Show backlinks panel for current note

### Telescope Pickers

Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) to be installed.

- `:HypoNotes` - Browse all notes with preview
  - `<CR>` - Open note
  - `<C-s>` - Open in horizontal split
  - `<C-v>` - Open in vertical split
  - `<C-t>` - Open in new tab

- `:HypoSearch [query]` - Full-text search with snippets
  - Shows highlighted context around matches
  - Same split/tab mappings as Notes picker

- `:HypoBacklinksPicker` - Find notes linking to current note
  - Shows context around each backlink
  - Jump to exact link location

- `:HypoNeighbors` - Show notes connected to current note (depth=1)
  - Display degree (connection count) for each neighbor
  - `:HypoNeighbors2` for depth=2 (may be slower)

### Diagnostics

- `:HypoDiag` - Open diagnostics panel
  - View backend info, cache stats, index freshness
  - Recent request timings
  - Actions: `[r]` reindex, `[c]` clear cache, `[q]` close

- `:checkhealth hypo` - Run health checks

## Configuration

### Full Configuration Example

```lua
require("hypo").setup({
  -- Backend: "cli" (default) or "api"
  backend = "cli",
  hypo_cmd = "hypo",          -- Path to hypo binary
  vault_path = "~/notes",     -- Required: path to vault
  db_path = nil,              -- Optional: custom DB path (default: vault/.hypo/index.sqlite)
  
  -- API backend settings (when backend = "api")
  api = {
    host = "127.0.0.1",
    port = 8765,
    token = nil,              -- Optional: Bearer token
    https = false,
    timeout = 3000,           -- Request timeout in ms
  },
  
  -- UI settings
  ui = {
    border = "rounded",       -- Border style for floating windows
    max_width = 84,
    max_height = 22,
  },
  
  -- Debounce settings
  debounce = {
    preview = 80,             -- Debounce preview updates (ms)
    search = 120,             -- Debounce search input (ms)
  },
  
  -- Feature toggles
  telescope = { enable = true },
  cmp = { 
    enable = true,
    max_items = 200,          -- Max completion items
    include_aliases = true,   -- Show aliases in completion docs
  },
  
  -- Cache TTLs (in milliseconds)
  cache_ttl = {
    notes = 5000,             -- List of all notes
    search = 2000,            -- Search results
    neighbours = 5000,        -- Neighbor relationships
  },
  
  -- Timeouts
  timeouts = {
    request_ms = 3000,        -- Default request timeout
  },
  
  -- Live refresh settings
  watch = {
    mode = "poll",            -- "poll", "subscribe", or "off"
    interval_ms = 2000,       -- Polling interval (when mode="poll")
  },
})
```

### nvim-cmp Integration

```lua
local cmp = require('cmp')
cmp.setup({
  sources = cmp.config.sources({
    { name = 'hypo' },        -- Add hypo completion source
    { name = 'nvim_lsp' },
    { name = 'buffer' },
    -- ... other sources
  })
})
```

The completion source triggers automatically when you type `[[` in markdown files.

## API Backend

For better performance on large vaults, you can run hypo as a server:

```bash
# Start the hypo server
hypo serve --vault ~/notes/vault --port 8765
```

Then configure hypo-nvim to use the API backend:

```lua
require("hypo").setup({
  backend = "api",
  vault_path = "~/notes/vault",  -- Still needed for some operations
  api = {
    host = "127.0.0.1",
    port = 8765,
    token = os.getenv("HYPO_API_TOKEN"),  -- Optional
  },
})
```

## Live Refresh

The plugin automatically monitors your vault for changes and invalidates caches:

- **Poll mode** (default): Checks DB modification time every 2 seconds when Neovim is focused
- **Subscribe mode**: (Not yet implemented) Would use `hypo watch` for real-time updates
- **Manual refresh**: Use `:HypoDiag` → `[r]` to reindex, or call `require('hypo.refresh').touch()`

Refresh is paused when Neovim loses focus to save resources.

## Default Keymaps

The plugin sets up these keymaps by default (you can override them):

```lua
vim.keymap.set("n", "gf", "<cmd>HypoGoto<cr>", { desc = "Hypo goto link" })
vim.keymap.set("n", "gp", "<cmd>HypoPreview<cr>", { desc = "Hypo preview link" })
vim.keymap.set("i", "<C-l>", "<cmd>HypoInsertLink<cr>", { desc = "Hypo insert [[id]]" })
vim.keymap.set("n", "<leader>hb", "<cmd>HypoBacklinks<cr>", { desc = "Hypo backlinks" })
```

## Troubleshooting

1. **No notes showing up**: 
   - Ensure `hypo` is installed and in your PATH
   - Run `hypo reindex --vault ~/notes/vault`
   - Check `:checkhealth hypo`

2. **Telescope pickers not working**:
   - Install telescope.nvim
   - Pickers gracefully degrade to warning messages if not available

3. **Completion not triggering**:
   - Ensure nvim-cmp is installed and configured
   - Check that you're in a markdown file
   - Verify `cmp.enable = true` in config

4. **Slow performance**:
   - Consider using the API backend for large vaults
   - Adjust cache TTLs if needed
   - Check `:HypoDiag` for request timings

## License

MIT
