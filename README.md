# Hypomnemata Integration with Neovim

A Neovim plugin for working with [Hypomnemata](https://github.com/cablehead/hypo) knowledge bases. Navigate, refactor, and manage multi-vault sessions without leaving Neovim.

## Features

- 🔗 **Link Navigation**: Jump to notes with `gf` on `[[id]]` links or preview with `gp`.
- 🔍 **Full-Text Search**: Telescope pickers for notes, backlinks, neighbours, and snippets.
- 📝 **Smart Completion**: Auto-complete note IDs with `[[` in markdown buffers.
- 🔄 **Live Refresh**: Polling or subscribe mode via `hypo watch --json` to keep caches fresh.
- 🧹 **Lint & Diagnostics**: Surface `hypo lint --json` results as diagnostics and quickfix entries, on-demand or on every refresh.
- ✂️ **Refactors**: Rename `^labels`, extract selections into new notes or transclusions, and normalize links with `hypo fmt`.
- 🖼️ **Asset Workflows**: Browse or paste assets into your vault and insert Markdown references automatically.
- 🧳 **Multi-Vault Sessions**: Switch vaults per tab, list recent locations, and show the active vault in your statusline.

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
      backend = {
        type = "cli",
        watch = { mode = "subscribe", debounce_ms = 250 },
      },
      lint = { auto = true },
      assets = { paste = { enable = true } },
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
- `:HypoGoto` or `gf` — Jump to note under cursor (on `[[id]]` links).
- `:HypoPreview` or `gp` — Preview a note in a floating window.
- `:HypoInsertLink` or `<C-l>` (insert mode) — Insert a note link.
- `:HypoBacklinks` — Show backlinks panel for the current note.

### Lint & Diagnostics
- `:HypoLint` — Lint the active vault and populate diagnostics/quickfix.
- `:HypoLintBuffer` — Lint only the current buffer.
- `:HypoLintOnChange` — Toggle auto-lint when notes change.

### Refactors
- `:HypoRenameLabel` — Rename the `^label` under the cursor.
- `:HypoRenameLabelGlobal` — Rename the `^label` across all references in the vault.
- `:HypoExtractNote` — Extract the current selection into a new note.
- `:HypoExtractTransclude` — Extract selection into a new note and insert a transclusion (`![[id#^label]]`).
- `:HypoNormalizeBuffer` — Run `hypo fmt --links --ids-only` for the current buffer.

### Lint & Auto-fix
- `:HypoLintApply` — Review and apply lint fixes interactively with Telescope.
- `:HypoLintApplyAll` — Apply all auto-fixable lint issues with confirmation.

### Assets
- `:HypoInsertAsset` — Pick an asset (or import a file) and insert a Markdown reference.
- `:HypoPasteImage` — Paste the clipboard into `assets/` and link it (requires `pngpaste`, `wl-paste`, or `xclip`).

### Multi-Vault
- `:HypoUseVault [path]` — Switch the active vault (per-tab by default).
- `:HypoVault` — Show the current vault.
- `:HypoRecentVaults` — Pick from recently used vaults.

### Telescope Pickers

Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

- `:HypoNotes` — Browse notes with previews.
- `:HypoSearch [query]` — Full-text search with highlighted snippets.
- `:HypoBacklinksPicker` — Find notes linking to the current note.
- `:HypoNeighbors` / `:HypoNeighbors2` — Explore graph neighbours by depth.

### Graph Visualization

- `:HypoGraphMap [depth]` — Show an ASCII graph mini-map of note relationships (depth 1 or 2).

### Diagnostics

- `:HypoDiag` — Open diagnostics panel with cache stats and backend info.
- `:checkhealth hypo` — Run health checks.

## Configuration

### Full Configuration Example

```lua
require("hypo").setup({
  backend = {
    type = "cli",              -- "cli" or "api"
    watch = {
      mode = "subscribe",       -- "subscribe", "poll", or "off"
      interval_ms = 2000,        -- Used when mode = "poll"
      debounce_ms = 250,
      flood = {
        max_batches = 8,         -- Max events in window
        window_ms = 800,         -- Time window for flood detection
      },
    },
  },
  hypo_cmd = "hypo",            -- Path to hypo binary
  vault_path = "~/notes",       -- Required: vault root
  db_path = nil,                 -- Optional: custom DB path

  api = {
    host = "127.0.0.1",
    port = 8765,
    token = nil,
    https = false,
    timeout = 3000,
  },

  ui = { border = "rounded", max_width = 84, max_height = 22 },
  debounce = { preview = 80, search = 120 },
  telescope = { enable = true },
  cmp = { enable = true, max_items = 200, include_aliases = true, rank_exact_id = true },
  cache_ttl = { notes = 5000, search = 2000, neighbours = 5000 },
  timeouts = { request_ms = 3000 },

  refactor = {
    confirm_global = true,       -- Prompt before global renames
  },

  lint = {
    auto = false,                -- enable :HypoLintOnChange automatically
    open_quickfix = true,
    max_problems = 500,
    virtual_text_width = 80,
    apply_preview = true,        -- Show diff preview before apply
  },

  graph = {
    map = {
      depth = 1,                 -- Default depth for graph visualization
      max_nodes = 200,           -- Limit rendering for performance
    },
  },

  assets = {
    dir = "assets",
    slugify = true,
    paste = { enable = false, provider = "auto" },
  },

  session = {
    per_tab = true,             -- Track vault per tab (or globally when false)
    recent_limit = 8,
  },
})
```

## Live Refresh

`hypo-nvim` monitors your vault and clears caches whenever files change:

- **Subscribe mode** (`backend.watch.mode = "subscribe"`): spawns `hypo watch --json --debounce-ms <n>` and reacts instantly to change events. If the watcher exits, the plugin falls back to polling and notifies you.
- **Poll mode** (`mode = "poll"`): checks the index mtime every `interval_ms` while Neovim has focus.
- **Manual refresh**: call `require('hypo.refresh').touch()` or run `:HypoDiag` → `[r]`.

## Lint & Diagnostics

`hypo lint --json` results surface as Neovim diagnostics and quickfix entries:

- Run `:HypoLint` for the entire vault or `:HypoLintBuffer` for the current buffer.
- Toggle automatic linting with `:HypoLintOnChange` to refresh on writes or incoming watcher events.
- Diagnostics live in namespace `hypo.nvim.lint` with custom highlights/signs (`HypoError`, `HypoWarn`, etc.).

### Interactive Lint Auto-fix

Review and apply automated fixes using Telescope:

```vim
:HypoLintApply      " Interactive picker
:HypoLintApplyAll   " Apply all fixes
```

Supported fixes:
- Simplify redundant links: `[[id|id]]` → `[[id]]`
- Migrate legacy links: `[[Title]]` → `[[id|Title]]`
- Remove duplicate block labels
- Add missing `id:` front-matter

The picker allows you to:
- Preview each fix
- Use `<Tab>` to toggle selection
- Press `<CR>` to apply selected fixes

## Refactors

- **Rename `^label`**: place the cursor on a `^label` definition or reference and run `:HypoRenameLabel`.
- **Extract selection**: visually select text, then `:HypoExtractNote` to create a new note and insert `[[id|Title]]` or `:HypoExtractTransclude` for `![[id#^label]]` transclusions. Content is written via the Hypo CLI to keep IDs canonical.
- **Normalize links**: run `:HypoNormalizeBuffer` to call `hypo fmt --links --ids-only` and reload the buffer if needed.

### Cross-Note Refactoring

Rename block references (`^labels`) across your entire vault:

```vim
:HypoRenameLabelGlobal
```

This will:
1. Find all notes linking to the current label
2. Update all references atomically
3. Preserve link integrity

Configure confirmation prompts:

```lua
require('hypo').setup({
  refactor = { confirm_global = true }
})
```

## Graph Visualization

Visualize note relationships with an ASCII mini-map:

```vim
:HypoGraphMap      " Depth 1 (neighbors)
:HypoGraphMap 2    " Depth 2 (neighbors + their neighbors)
```

Keybindings in the graph window:
- `j/k`: Navigate up/down
- `<CR>`: Open selected note
- `r`: Refresh graph data
- `q` or `<Esc>`: Close

Configure depth and performance:

```lua
require('hypo').setup({
  graph = {
    map = {
      depth = 1,        -- Default depth
      max_nodes = 200,  -- Limit for performance
    }
  }
})
```

## Enhanced Completion

The nvim-cmp source now features smarter ranking:

1. **Exact ID prefix match** — highest priority
2. **Title starts-with**
3. **Alias exact match**
4. **Alias starts-with**
5. **Substring match** in title/alias
6. **Fuzzy match** — fallback

The completion documentation now displays:
```
Title of the Note
aliases: alias1, alias2, alias3
id: note_id_123
```

Configure completion behavior:

```lua
require('hypo').setup({
  cmp = {
    max_items = 200,        -- Limit candidates for performance
    include_aliases = true,  -- Complete on aliases
    rank_exact_id = true,    -- Prioritize exact ID matches
  }
})
```

## Watcher Status

Add watcher status to your statusline:

```lua
vim.o.statusline = '%{luaeval("require(\'hypo.refresh\').status()")} ...'
```

Or use the helper function:

```lua
require('hypo.ui.signs').statusline_component()
```

Status indicators:
- `● watching` — Active file watcher (subscribe mode)
- `○ polling` — Fallback timer mode
- `× offline` — Provider unavailable

### Flood Protection

The watcher now includes flood protection to handle rapid file changes:

```lua
require('hypo').setup({
  backend = {
    watch = {
      flood = {
        max_batches = 8,   -- Events in window
        window_ms = 800,   -- Time window (ms)
      }
    }
  }
})
```

When more than `max_batches` events occur within `window_ms`, the watcher coalesces them into a single refresh to prevent overwhelming the system.

## Asset Workflows

- **Insert**: `:HypoInsertAsset` lists files under `assets/` (relative to your vault). Import external files by copying or moving them into the assets directory before inserting the Markdown reference. Images become `![alt](assets/file.png)`; other files use `[label](assets/file.pdf)`.
- **Paste**: `:HypoPasteImage` saves the clipboard into `assets/` using `pngpaste`, `wl-paste`, or `xclip` and inserts an image reference. Enable via `assets.paste.enable = true`.

## Multi-Vault Sessions

The plugin keeps per-tab vault context by default:

- Use `:HypoUseVault` to switch the active vault (prompts for a path when omitted).
- Recently used vaults persist under `stdpath('cache')/hypo_recent_vaults.json`; pick them with `:HypoRecentVaults`.
- `require('hypo.features.session').status()` returns a statusline-friendly string such as `[hypo: notes]`.

## Default Keymaps

- `gf` — `:HypoGoto`
- `gp` — `:HypoPreview`
- `<C-l>` (insert) — `:HypoInsertLink`
- `<leader>hb` — `:HypoBacklinks`
- `<leader>hl` — `:HypoLint`
- `<leader>hr` — `:HypoRenameLabel`
- `<leader>he` (visual) — `:HypoExtractNote`
- `<leader>hE` (visual) — `:HypoExtractTransclude`
- `<leader>ha` — `:HypoInsertAsset`
- `<leader>hv` — `:HypoUseVault`

## API Backend

Configure `backend.type = "api"` to talk to a running `hypo serve` instance. Subscribe mode is CLI-only; polling remains available for API backends.

## License

MIT
