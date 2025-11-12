-- graphmap.lua
-- Lightweight ASCII graph visualization for note relationships
local M = {}

local provider = require('hypo.provider')
local config = require('hypo.config')

local state = {
  bufnr = nil,
  winnr = nil,
  current_id = nil,
  nodes = {},
  selected_idx = 1,
}

-- Truncate string to max length
local function truncate(str, max_len)
  if #str <= max_len then
    return str
  end
  return str:sub(1, max_len - 3) .. '...'
end

-- Render ASCII graph
local function render_graph(center_id, nodes, depth)
  local lines = {}
  local conf = config.get()
  local max_nodes = (conf.graph and conf.graph.map and conf.graph.map.max_nodes) or 200

  table.insert(lines, '┌─ Graph: ' .. truncate(center_id, 30) .. ' (depth ' .. depth .. ') ─────┐')
  table.insert(lines, '│' .. string.rep(' ', 50) .. '│')

  if not nodes or #nodes == 0 then
    table.insert(lines, '│  No connected notes found' .. string.rep(' ', 23) .. '│')
  else
    local display_nodes = {}
    for i, node in ipairs(nodes) do
      if i > max_nodes then
        break
      end
      table.insert(display_nodes, node)
    end

    -- Simple layout: show center and connected nodes
    local center_line = '│     ' .. truncate(center_id, 30)
    local padding = 52 - #center_line
    if padding < 0 then
      padding = 0
    end
    table.insert(lines, center_line .. string.rep(' ', padding) .. '│')

    for i, node in ipairs(display_nodes) do
      local id = node.id or node
      local title = node.title or id
      local display = truncate(title, 30)
      local prefix = i == state.selected_idx and '  → ' or '    '
      local line = '│' .. prefix .. display
      local pad = 52 - #line
      if pad < 0 then
        pad = 0
      end
      table.insert(lines, line .. string.rep(' ', pad) .. '│')
    end

    if #nodes > max_nodes then
      table.insert(lines, '│  ... and ' .. (#nodes - max_nodes) .. ' more' .. string.rep(' ', 23) .. '│')
    end
  end

  table.insert(lines, '│' .. string.rep(' ', 50) .. '│')
  table.insert(lines, '│ j/k: nav | <CR>: open | r: refresh | q: close  │')
  table.insert(lines, '└' .. string.rep('─', 50) .. '┘')

  return lines
end

-- Update the display
local function update_display()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local conf = config.get()
  local depth = (conf.graph and conf.graph.map and conf.graph.map.depth) or 1

  vim.api.nvim_buf_set_option(state.bufnr, 'modifiable', true)
  local lines = render_graph(state.current_id, state.nodes, depth)
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.bufnr, 'modifiable', false)
end

-- Navigate selection
local function move_selection(delta)
  if #state.nodes == 0 then
    return
  end

  state.selected_idx = state.selected_idx + delta
  if state.selected_idx < 1 then
    state.selected_idx = 1
  elseif state.selected_idx > #state.nodes then
    state.selected_idx = #state.nodes
  end

  update_display()
end

-- Open selected note
local function open_selected()
  if state.selected_idx < 1 or state.selected_idx > #state.nodes then
    return
  end

  local node = state.nodes[state.selected_idx]
  local id = node.id or node

  M.close()

  -- Use HypoGoto to open the note
  vim.schedule(function()
    require('hypo.features.goto').goto_note(id)
  end)
end

-- Refresh graph data
local function refresh()
  if not state.current_id then
    return
  end

  local conf = config.get()
  local depth = (conf.graph and conf.graph.map and conf.graph.map.depth) or 1

  provider.graph(state.current_id, depth, function(ok, graph_data)
    if ok and graph_data and graph_data.nodes then
      state.nodes = graph_data.nodes
      state.selected_idx = 1
      update_display()
    else
      vim.notify('Failed to refresh graph', vim.log.levels.WARN)
    end
  end)
end

function M.close()
  if state.winnr and vim.api.nvim_win_is_valid(state.winnr) then
    vim.api.nvim_win_close(state.winnr, true)
  end
  state.winnr = nil
  state.bufnr = nil
  state.current_id = nil
  state.nodes = {}
  state.selected_idx = 1
end

function M.open(depth)
  depth = depth or 1

  -- Get current note ID
  local bufpath = vim.api.nvim_buf_get_name(0)
  if bufpath == '' then
    vim.notify('Not in a note buffer', vim.log.levels.WARN)
    return
  end

  local note_id = vim.fn.fnamemodify(bufpath, ':t:r')
  state.current_id = note_id

  -- Fetch graph data
  provider.graph(note_id, depth, function(ok, graph_data)
    if not ok then
      vim.notify('Failed to get graph data: ' .. tostring(graph_data), vim.log.levels.ERROR)
      return
    end

    state.nodes = (graph_data and graph_data.nodes) or {}
    state.selected_idx = 1

    -- Create floating window
    local buf = vim.api.nvim_create_buf(false, true)
    state.bufnr = buf

    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'hypo-graph')

    -- Set up window
    local width = 54
    local height = math.min(20, #state.nodes + 8)
    local conf = config.get()
    local ui_conf = conf.ui or {}
    local border = ui_conf.border or 'rounded'

    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = 'minimal',
      border = border,
    })
    state.winnr = win

    -- Set up keybinds
    local opts = { buffer = buf, nowait = true, silent = true }
    vim.keymap.set('n', 'j', function()
      move_selection(1)
    end, opts)
    vim.keymap.set('n', 'k', function()
      move_selection(-1)
    end, opts)
    vim.keymap.set('n', '<CR>', open_selected, opts)
    vim.keymap.set('n', 'r', refresh, opts)
    vim.keymap.set('n', 'q', M.close, opts)
    vim.keymap.set('n', '<Esc>', M.close, opts)

    -- Render initial display
    update_display()
  end)
end

return M
