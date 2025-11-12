-- cmp/source.lua
-- nvim-cmp source for hypo note completion
local M = {}
local config = require('hypo.config')
local provider = require('hypo.provider')

local source = {}

function source:new()
  return setmetatable({}, { __index = source })
end

function source:get_trigger_characters()
  return { '[' }
end

function source:get_keyword_pattern()
  -- Match characters after [[
  return [=[\[\[.*]=]
end

-- Check if we should trigger completion
function source:is_available()
  local conf = config.get()
  if not conf.cmp or not conf.cmp.enable then
    return false
  end

  -- Only in markdown files
  local ft = vim.bo.filetype
  if ft ~= 'markdown' and ft ~= 'md' then
    return false
  end

  return true
end

-- Fuzzy filter notes by prefix
local function filter_notes(notes, prefix)
  if not prefix or prefix == '' then
    return notes
  end

  local results = {}
  local lower_prefix = prefix:lower()

  -- Sort by match quality: exact > starts_with > contains
  local exact = {}
  local starts = {}
  local contains = {}

  for _, note in ipairs(notes) do
    local id = note.id or ''
    local lower_id = id:lower()

    if lower_id == lower_prefix then
      table.insert(exact, note)
    elseif vim.startswith(lower_id, lower_prefix) then
      table.insert(starts, note)
    elseif lower_id:find(lower_prefix, 1, true) then
      table.insert(contains, note)
    end
  end

  -- Combine results
  vim.list_extend(results, exact)
  vim.list_extend(results, starts)
  vim.list_extend(results, contains)

  return results
end

function source:complete(params, callback)
  -- Check if we're after [[
  local line = params.context.cursor_before_line
  local col = params.context.cursor.character

  -- Look for [[ before cursor
  local before = line:sub(1, col)
  local open_bracket = before:find('%[%[', 1, true)

  if not open_bracket then
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Extract prefix after [[
  local prefix = before:sub(open_bracket + 2)

  -- Check if we're in a code fence (simple check)
  local all_lines = vim.api.nvim_buf_get_lines(params.context.bufnr, 0, params.context.cursor.line, false)
  local fence_count = 0
  for _, l in ipairs(all_lines) do
    if l:match('^```') then
      fence_count = fence_count + 1
    end
  end
  if fence_count % 2 == 1 then
    -- We're inside a code fence
    callback({ items = {}, isIncomplete = false })
    return
  end

  -- Fetch notes
  provider.list_notes(function(ok, notes)
    if not ok or not notes then
      callback({ items = {}, isIncomplete = false })
      return
    end

    -- Filter by prefix
    local filtered = filter_notes(notes, prefix)

    -- Build completion items
    local conf = config.get()
    local max_items = (conf.cmp and conf.cmp.max_items) or 200
    local include_aliases = (conf.cmp and conf.cmp.include_aliases) or true

    local items = {}
    for i, note in ipairs(filtered) do
      if i > max_items then
        break
      end

      local doc_parts = {}
      if note.title then
        table.insert(doc_parts, note.title)
      end
      if include_aliases and note.aliases and #note.aliases > 0 then
        table.insert(doc_parts, 'Aliases: ' .. table.concat(note.aliases, ', '))
      end

      table.insert(items, {
        label = note.id,
        insertText = note.id,
        kind = 18, -- vim.lsp.protocol.CompletionItemKind.Reference
        documentation = #doc_parts > 0 and table.concat(doc_parts, '\n') or nil,
        filterText = note.id,
        sortText = string.format('%03d_%s', i, note.id),
        data = { note = note },
      })
    end

    callback({
      items = items,
      isIncomplete = #filtered > max_items,
    })
  end)
end

function M.new()
  return source:new()
end

return M
