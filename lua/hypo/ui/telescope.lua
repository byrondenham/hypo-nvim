-- ui/telescope.lua
-- Production-quality Telescope pickers for hypo
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
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local entry_display = require('telescope.pickers.entry_display')

local provider = require('hypo.provider')
local config = require('hypo.config')

-- Create a previewer for note content
local function note_previewer()
  return previewers.new_buffer_previewer({
    title = 'Note Preview',
    define_preview = function(self, entry, status)
      if not entry or not entry.value or not entry.value.id then
        return
      end

      local id = entry.value.id
      local title = entry.value.title or id

      -- Set title
      vim.api.nvim_buf_set_name(self.state.bufnr, '[' .. id .. '] ' .. title)

      -- Load note content
      provider.locate(id, function(ok, loc)
        if not ok or not loc or not loc.path then
          vim.schedule(function()
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { 'Failed to locate note' })
          end)
          return
        end

        -- Read file content (first 30 lines)
        vim.schedule(function()
          local file = io.open(loc.path, 'r')
          if file then
            local lines = {}
            local count = 0
            for line in file:lines() do
              table.insert(lines, line)
              count = count + 1
              if count >= 30 then
                break
              end
            end
            file:close()

            if vim.api.nvim_buf_is_valid(self.state.bufnr) then
              vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
              vim.bo[self.state.bufnr].filetype = 'markdown'
            end
          end
        end)
      end)
    end,
  })
end

-- Display formatter for notes
local function make_notes_displayer()
  local displayer = entry_display.create({
    separator = ' │ ',
    items = {
      { width = 12 },
      { remaining = true },
    },
  })

  return function(entry)
    return displayer({
      { entry.value.id or '', 'TelescopeResultsIdentifier' },
      { entry.value.title or '', 'TelescopeResultsComment' },
    })
  end
end

-- Open note helper
local function open_note(id, mode)
  mode = mode or 'edit'
  provider.locate(id, function(ok, loc)
    vim.schedule(function()
      if ok and loc and loc.path then
        local cmd = mode .. ' ' .. vim.fn.fnameescape(loc.path)
        vim.cmd(cmd)
        if loc.lines and loc.lines[1] then
          vim.api.nvim_win_set_cursor(0, { loc.lines[1], 0 })
        end
      else
        vim.notify('Could not locate note: ' .. id, vim.log.levels.ERROR)
      end
    end)
  end)
end

-- Notes Picker
function M.notes()
  provider.list_notes(function(ok, notes)
    if not ok or not notes then
      vim.notify('Failed to list notes', vim.log.levels.ERROR)
      return
    end

    pickers
      .new({}, {
        prompt_title = 'Hypo Notes',
        finder = finders.new_table({
          results = notes,
          entry_maker = function(note)
            return {
              value = note,
              display = make_notes_displayer(),
              ordinal = note.id .. ' ' .. (note.title or ''),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = note_previewer(),
        attach_mappings = function(prompt_bufnr, map)
          local function open_selected(mode)
            return function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection and selection.value and selection.value.id then
                open_note(selection.value.id, mode)
              end
            end
          end

          actions.select_default:replace(open_selected('edit'))
          map('i', '<C-s>', open_selected('split'))
          map('n', '<C-s>', open_selected('split'))
          map('i', '<C-v>', open_selected('vsplit'))
          map('n', '<C-v>', open_selected('vsplit'))
          map('i', '<C-t>', open_selected('tabnew'))
          map('n', '<C-t>', open_selected('tabnew'))

          return true
        end,
      })
      :find()
  end)
end

-- Search Picker
function M.search(query)
  if not query then
    vim.ui.input({ prompt = 'Search: ' }, function(input)
      if input and input ~= '' then
        M.search(input)
      end
    end)
    return
  end

  provider.search(query, { snippets = true, limit = 200 }, function(ok, results)
    if not ok or not results then
      vim.notify('Search failed', vim.log.levels.ERROR)
      return
    end

    if #results == 0 then
      vim.notify('No results found', vim.log.levels.INFO)
      return
    end

    -- Process snippets: strip <b> tags for display, keep track of highlights
    for _, result in ipairs(results) do
      if result.snippet then
        -- Simple tag stripping for now
        result.display_snippet = result.snippet:gsub('<b>', ''):gsub('</b>', '')
      end
    end

    local displayer = entry_display.create({
      separator = ' │ ',
      items = {
        { width = 12 },
        { remaining = true },
      },
    })

    pickers
      .new({}, {
        prompt_title = 'Search: ' .. query,
        finder = finders.new_table({
          results = results,
          entry_maker = function(result)
            return {
              value = result,
              display = function(entry)
                return displayer({
                  { entry.value.id or '', 'TelescopeResultsIdentifier' },
                  { entry.value.display_snippet or entry.value.snippet or entry.value.title or '', 'Normal' },
                })
              end,
              ordinal = result.id .. ' ' .. (result.snippet or result.title or ''),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = note_previewer(),
        attach_mappings = function(prompt_bufnr, map)
          local function open_selected(mode)
            return function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection and selection.value and selection.value.id then
                open_note(selection.value.id, mode)
              end
            end
          end

          actions.select_default:replace(open_selected('edit'))
          map('i', '<C-s>', open_selected('split'))
          map('n', '<C-s>', open_selected('split'))
          map('i', '<C-v>', open_selected('vsplit'))
          map('n', '<C-v>', open_selected('vsplit'))
          map('i', '<C-t>', open_selected('tabnew'))
          map('n', '<C-t>', open_selected('tabnew'))

          return true
        end,
      })
      :find()
  end)
end

-- Backlinks Picker
function M.backlinks(id)
  local cur_id = id
    or (function()
      local link = require('hypo.util.link')
      -- Try to get ID from current file or link under cursor
      local under = link.under_cursor()
      if under and under.id then
        return under.id
      end
      -- Try to extract from filename
      local fname = vim.fn.expand('%:t:r')
      if fname and fname ~= '' then
        return fname
      end
      return nil
    end)()

  if not cur_id then
    vim.notify('No current note ID found', vim.log.levels.WARN)
    return
  end

  provider.backrefs(cur_id, { context = 1 }, function(ok, refs)
    if not ok or not refs then
      vim.notify('Failed to get backlinks', vim.log.levels.ERROR)
      return
    end

    if #refs == 0 then
      vim.notify('No backlinks found', vim.log.levels.INFO)
      return
    end

    local displayer = entry_display.create({
      separator = ' │ ',
      items = {
        { width = 12 },
        { remaining = true },
      },
    })

    pickers
      .new({}, {
        prompt_title = 'Backlinks to: ' .. cur_id,
        finder = finders.new_table({
          results = refs,
          entry_maker = function(ref)
            local source_id = ref.source or ref.id or '?'
            local context = ref.context or ref.snippet or ''
            return {
              value = ref,
              display = function(entry)
                return displayer({
                  { source_id, 'TelescopeResultsIdentifier' },
                  { context:gsub('\n', ' '):sub(1, 60), 'Normal' },
                })
              end,
              ordinal = source_id .. ' ' .. context,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = note_previewer(),
        attach_mappings = function(prompt_bufnr, map)
          local function open_selected(mode)
            return function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection and selection.value then
                local source_id = selection.value.source or selection.value.id
                if source_id then
                  open_note(source_id, mode)
                end
              end
            end
          end

          actions.select_default:replace(open_selected('edit'))
          map('i', '<C-s>', open_selected('split'))
          map('n', '<C-s>', open_selected('split'))
          map('i', '<C-v>', open_selected('vsplit'))
          map('n', '<C-v>', open_selected('vsplit'))
          map('i', '<C-t>', open_selected('tabnew'))
          map('n', '<C-t>', open_selected('tabnew'))

          return true
        end,
      })
      :find()
  end)
end

-- Neighbours Picker
function M.neighbours(id, depth)
  local cur_id = id
    or (function()
      local link = require('hypo.util.link')
      local under = link.under_cursor()
      if under and under.id then
        return under.id
      end
      local fname = vim.fn.expand('%:t:r')
      if fname and fname ~= '' then
        return fname
      end
      return nil
    end)()

  if not cur_id then
    vim.notify('No current note ID found', vim.log.levels.WARN)
    return
  end

  depth = depth or 1

  if depth > 1 then
    vim.notify('Fetching depth=' .. depth .. ' neighbors (this may take a moment)...', vim.log.levels.INFO)
  end

  provider.neighbours(cur_id, depth, function(ok, neighbours)
    if not ok or not neighbours then
      vim.notify('Failed to get neighbours', vim.log.levels.ERROR)
      return
    end

    if #neighbours == 0 then
      vim.notify('No neighbours found', vim.log.levels.INFO)
      return
    end

    local displayer = entry_display.create({
      separator = ' │ ',
      items = {
        { width = 12 },
        { width = 40 },
        { remaining = true },
      },
    })

    pickers
      .new({}, {
        prompt_title = 'Neighbours of ' .. cur_id .. ' (depth=' .. depth .. ')',
        finder = finders.new_table({
          results = neighbours,
          entry_maker = function(neighbour)
            local degree = neighbour.degree or 0
            return {
              value = neighbour,
              display = function(entry)
                return displayer({
                  { entry.value.id or '', 'TelescopeResultsIdentifier' },
                  { entry.value.title or '', 'Normal' },
                  { string.format('(degree: %d)', degree), 'TelescopeResultsComment' },
                })
              end,
              ordinal = neighbour.id .. ' ' .. (neighbour.title or ''),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        previewer = note_previewer(),
        attach_mappings = function(prompt_bufnr, map)
          local function open_selected(mode)
            return function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection and selection.value and selection.value.id then
                open_note(selection.value.id, mode)
              end
            end
          end

          actions.select_default:replace(open_selected('edit'))
          map('i', '<C-s>', open_selected('split'))
          map('n', '<C-s>', open_selected('split'))
          map('i', '<C-v>', open_selected('vsplit'))
          map('n', '<C-v>', open_selected('vsplit'))
          map('i', '<C-t>', open_selected('tabnew'))
          map('n', '<C-t>', open_selected('tabnew'))

          return true
        end,
      })
      :find()
  end)
end

return M
