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

-- Fuzzy filter notes by prefix with multi-tier ranking
local function filter_notes(notes, prefix, conf)
  if not prefix or prefix == '' then
    return notes
  end

  local lower_prefix = prefix:lower()
  local include_aliases = (conf.cmp and conf.cmp.include_aliases) ~= false
  local rank_exact_id = (conf.cmp and conf.cmp.rank_exact_id) ~= false

  -- Tier 1: Exact ID match
  local exact_id = {}
  -- Tier 2: Title starts-with
  local title_starts = {}
  -- Tier 3: Alias exact match
  local alias_exact = {}
  -- Tier 4: Alias starts-with
  local alias_starts = {}
  -- Tier 5: Substring match in title/alias
  local substring = {}
  -- Tier 6: Fuzzy match (fallback)
  local fuzzy = {}

  for _, note in ipairs(notes) do
    local id = note.id or ''
    local lower_id = id:lower()
    local title = note.title or ''
    local lower_title = title:lower()
    local matched = false

    -- Check exact ID match
    if rank_exact_id and lower_id == lower_prefix then
      table.insert(exact_id, note)
      matched = true
    elseif not matched and vim.startswith(lower_id, lower_prefix) then
      -- ID starts with prefix (not exact)
      table.insert(exact_id, note)
      matched = true
    end

    -- Check title starts-with
    if not matched and vim.startswith(lower_title, lower_prefix) then
      table.insert(title_starts, note)
      matched = true
    end

    -- Check aliases
    if not matched and include_aliases and note.aliases and #note.aliases > 0 then
      for _, alias in ipairs(note.aliases) do
        local lower_alias = alias:lower()
        if lower_alias == lower_prefix then
          table.insert(alias_exact, note)
          matched = true
          break
        elseif vim.startswith(lower_alias, lower_prefix) then
          table.insert(alias_starts, note)
          matched = true
          break
        end
      end
    end

    -- Check substring in title or aliases
    if not matched then
      if lower_title:find(lower_prefix, 1, true) then
        table.insert(substring, note)
        matched = true
      elseif include_aliases and note.aliases and #note.aliases > 0 then
        for _, alias in ipairs(note.aliases) do
          if alias:lower():find(lower_prefix, 1, true) then
            table.insert(substring, note)
            matched = true
            break
          end
        end
      end
    end

    -- Fuzzy fallback (simple check if characters appear in order)
    if not matched then
      local pattern = lower_prefix:gsub('.', function(c)
        return c .. '.-'
      end)
      if lower_id:match(pattern) or lower_title:match(pattern) then
        table.insert(fuzzy, note)
      end
    end
  end

  -- Combine all tiers
  local results = {}
  vim.list_extend(results, exact_id)
  vim.list_extend(results, title_starts)
  vim.list_extend(results, alias_exact)
  vim.list_extend(results, alias_starts)
  vim.list_extend(results, substring)
  vim.list_extend(results, fuzzy)

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

    -- Filter by prefix with ranking
    local conf = config.get()
    local filtered = filter_notes(notes, prefix, conf)

    -- Build completion items
    local max_items = (conf.cmp and conf.cmp.max_items) or 200
    local include_aliases = (conf.cmp and conf.cmp.include_aliases) ~= false

    local items = {}
    for i, note in ipairs(filtered) do
      if i > max_items then
        break
      end

      -- Build documentation with title, aliases, and ID
      local doc_parts = {}
      if note.title and note.title ~= '' then
        table.insert(doc_parts, note.title)
      end
      if include_aliases and note.aliases and #note.aliases > 0 then
        table.insert(doc_parts, 'aliases: ' .. table.concat(note.aliases, ', '))
      end
      if note.id then
        table.insert(doc_parts, 'id: ' .. note.id)
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
