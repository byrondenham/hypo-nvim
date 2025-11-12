-- ui/telescope.lua
-- Safe Telescope pickers for hypo (notes, search, backrefs, neighbours)
local M = {}
local has_ts, telescope = pcall(require, 'telescope')
if not has_ts then
  -- export no-ops so callers don't need to check
  M.notes = function()
    vim.notify('Telescope not installed', vim.log.levels.WARN)
  end
  M.search = function()
    vim.notify('Telescope not installed', vim.log.levels.WARN)
  end
  M.backlinks = function()
    vim.notify('Telescope not installed', vim.log.levels.WARN)
  end
  M.neighbours = function()
    vim.notify('Telescope not installed', vim.log.levels.WARN)
  end
  return M
end

local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local entry_display = require('telescope.pickers.entry_display')

local provider = require('hypo.provider')

local function make_display(opts)
  local dis = entry_display.create({
    separator = ' ',
    items = {
      { width = 12 },
      { remaining = true },
    },
  })
  return function(entry)
    return dis({ entry.id or '', entry.title or entry.snippet or '' })
  end
end

function M.notes()
  pickers
    .new({}, {
      prompt_title = 'Hypo Notes',
      finder = finders.new_table({
        results = {},
        entry_maker = function(line)
          return {
            value = line,
            display = (line.id and ('[' .. line.id .. '] ' .. (line.title or ''))) or tostring(line),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(_, map)
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local open = function(prompt_bufnr)
          local sel = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if sel and sel.value and sel.value.id then
            local id = sel.value.id
            require('hypo.provider').locate({ id = id }, function(ok, loc)
              if ok and loc and loc.path then
                vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
                if loc.lines and loc.lines[1] then
                  vim.api.nvim_win_set_cursor(0, { loc.lines[1], 0 })
                end
              else
                vim.notify('Could not locate note: ' .. tostring(loc), vim.log.levels.ERROR)
              end
            end)
          end
        end
        map('i', '<CR>', open)
        map('n', '<CR>', open)
        return true
      end,
    })
    :find()
  -- populate asynchronously
  provider.list_notes(function(ok, notes)
    if ok and notes and #notes > 0 then
      -- reload picker with results (simple approach: reopen)
      -- For now, user can re-run command. Advanced: use telescope live_finder
    end
  end)
end

function M.search()
  local input = vim.fn.input('Search: ')
  if input == '' then
    return
  end
  pickers
    .new({}, {
      prompt_title = 'Hypo Search: ' .. input,
      finder = finders.new_table({
        results = {},
        entry_maker = function(item)
          return {
            value = item,
            display = (item.id and (item.id .. '  ' .. (item.title or ''))) or tostring(item),
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(_, map)
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        local open = function(prompt_bufnr)
          local sel = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if sel and sel.value and sel.value.id then
            require('hypo.provider').locate({ id = sel.value.id }, function(ok, loc)
              if ok and loc and loc.path then
                vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
                if loc.lines and loc.lines[1] then
                  vim.api.nvim_win_set_cursor(0, { loc.lines[1], 0 })
                end
              else
                vim.notify('Could not locate note', vim.log.levels.ERROR)
              end
            end)
          end
        end
        map('i', '<CR>', open)
        map('n', '<CR>', open)
        return true
      end,
    })
    :find()

  provider.search(input, { snippets = true }, function(ok, results)
    if not ok then
      vim.notify('Search failed: ' .. tostring(results), vim.log.levels.ERROR)
      return
    end
    -- Ideally feed results into existing picker; for simplicity, open a quickfix or print
    if #results == 0 then
      vim.notify('No results', vim.log.levels.INFO)
      return
    end
    local items = {}
    for _, r in ipairs(results) do
      table.insert(items, r)
    end
    -- open first result
    require('hypo.provider').locate({ id = items[1].id }, function(ok2, loc)
      if ok2 and loc and loc.path then
        vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
      end
    end)
  end)
end

function M.backlinks(id)
  local cur_id = id or require('hypo.util.link').current_id()
  if not cur_id then
    vim.notify('No current note id', vim.log.levels.WARN)
    return
  end
  provider.backrefs(cur_id, { context = 1 }, function(ok, refs)
    if not ok then
      vim.notify('backrefs failed: ' .. tostring(refs), vim.log.levels.ERROR)
      return
    end
    local results = {}
    for _, r in ipairs(refs) do
      table.insert(results, r)
    end
    pickers
      .new({}, {
        prompt_title = 'Hypo Backrefs: ' .. cur_id,
        finder = finders.new_table({ results = results }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(_, map)
          local actions = require('telescope.actions')
          local action_state = require('telescope.actions.state')
          local open = function(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if sel and sel[1] and sel[1].source then
              require('hypo.provider').locate({ id = sel[1].source }, function(ok2, loc)
                if ok2 and loc and loc.path then
                  vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
                  if sel[1].start then
                    vim.api.nvim_win_set_cursor(0, { sel[1].start, 0 })
                  end
                end
              end)
            end
          end
          map('i', '<CR>', open)
          map('n', '<CR>', open)
          return true
        end,
      })
      :find()
  end)
end

function M.neighbours(id, depth)
  local cur_id = id or require('hypo.util.link').current_id()
  if not cur_id then
    vim.notify('No current note id', vim.log.levels.WARN)
    return
  end
  depth = depth or 1
  provider.neighbours(cur_id, depth, function(ok, res)
    if not ok then
      vim.notify('neighbours failed: ' .. tostring(res), vim.log.levels.ERROR)
      return
    end
    local results = res or {}
    pickers
      .new({}, {
        prompt_title = 'Hypo neighbours: ' .. cur_id,
        finder = finders.new_table({ results = results }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(_, map)
          local actions = require('telescope.actions')
          local action_state = require('telescope.actions.state')
          local open = function(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if sel and sel.value and sel.value.id then
              require('hypo.provider').locate({ id = sel.value.id }, function(ok2, loc)
                if ok2 and loc and loc.path then
                  vim.cmd('edit ' .. vim.fn.fnameescape(loc.path))
                end
              end)
            end
          end
          map('i', '<CR>', open)
          map('n', '<CR>', open)
          return true
        end,
      })
      :find()
  end)
end

return M
