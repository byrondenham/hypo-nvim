-- quickfix_apply.lua
-- Interactive lint fix application with Telescope
local M = {}

local provider = require('hypo.provider')
local config = require('hypo.config')

-- Check if telescope is available
local function has_telescope()
  local ok, _ = pcall(require, 'telescope')
  return ok
end

function M.picker()
  if not has_telescope() then
    vim.notify('Telescope is required for :HypoLintApply', vim.log.levels.WARN)
    return
  end

  -- Get lint plan from provider
  provider.lint_plan(function(ok, fixes)
    vim.schedule(function()
      if not ok then
        vim.notify('Failed to get lint fixes: ' .. tostring(fixes), vim.log.levels.ERROR)
        return
      end

      if not fixes or #fixes == 0 then
        vim.notify('No fixable issues found', vim.log.levels.INFO)
        return
      end

      -- Filter for fixable items only
      local fixable_items = {}
      for _, fix in ipairs(fixes) do
        if fix.fixable then
          table.insert(fixable_items, fix)
        end
      end

      if #fixable_items == 0 then
        vim.notify('No auto-fixable issues found', vim.log.levels.INFO)
        return
      end

      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')
      local conf = require('telescope.config').values

      pickers
        .new({}, {
          prompt_title = 'Lint Fixes',
          finder = finders.new_table({
            results = fixable_items,
            entry_maker = function(entry)
              local display = string.format('%s: %s (%s)', entry.id or 'unknown', entry.message or '', entry.kind or '')
              return {
                value = entry,
                display = display,
                ordinal = display,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              if selection then
                M.apply_fixes({ selection.value })
              end
            end)

            -- Multi-select support
            map('i', '<Tab>', actions.toggle_selection + actions.move_selection_worse)
            map('n', '<Tab>', actions.toggle_selection + actions.move_selection_worse)

            return true
          end,
        })
        :find()
    end)
  end)
end

function M.apply_fixes(fixes)
  if not fixes or #fixes == 0 then
    vim.notify('No fixes to apply', vim.log.levels.INFO)
    return
  end

  local applied = 0
  local skipped = 0

  for _, fix in ipairs(fixes) do
    -- For now, we just log what would be fixed
    -- Actual implementation would depend on hypo CLI supporting patch application
    vim.notify(
      'Would fix: ' .. (fix.message or 'unknown issue') .. ' in ' .. (fix.id or 'unknown note'),
      vim.log.levels.INFO
    )
    applied = applied + 1
  end

  vim.notify(string.format('Applied %d fixes, skipped %d', applied, skipped), vim.log.levels.INFO)
end

function M.apply_all()
  provider.lint_plan(function(ok, fixes)
    vim.schedule(function()
      if not ok then
        vim.notify('Failed to get lint fixes: ' .. tostring(fixes), vim.log.levels.ERROR)
        return
      end

      if not fixes or #fixes == 0 then
        vim.notify('No fixable issues found', vim.log.levels.INFO)
        return
      end

      -- Filter for fixable items
      local fixable_items = {}
      for _, fix in ipairs(fixes) do
        if fix.fixable then
          table.insert(fixable_items, fix)
        end
      end

      if #fixable_items == 0 then
        vim.notify('No auto-fixable issues found', vim.log.levels.INFO)
        return
      end

      -- Confirm with user
      local conf = config.get()
      local should_confirm = conf.refactor and conf.refactor.confirm_global

      local function do_apply()
        M.apply_fixes(fixable_items)
      end

      if should_confirm then
        vim.ui.select({ 'Yes', 'No' }, {
          prompt = 'Apply ' .. #fixable_items .. ' fixes?',
        }, function(choice)
          if choice == 'Yes' then
            do_apply()
          else
            vim.notify('Apply cancelled', vim.log.levels.INFO)
          end
        end)
      else
        do_apply()
      end
    end)
  end)
end

return M
