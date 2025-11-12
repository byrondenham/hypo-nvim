-- refactor_xnote.lua
-- Cross-note refactoring: rename ^labels across vault
local M = {}

local provider = require('hypo.provider')
local config = require('hypo.config')

-- Parse the current line to extract ^label if present
local function get_label_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  -- Try to find ^label pattern on this line
  local label = line:match('%^([%w_%-]+)')
  if not label then
    return nil
  end

  return label
end

-- Get the note ID of the current buffer
local function get_current_note_id()
  local bufpath = vim.api.nvim_buf_get_name(0)
  if bufpath == '' then
    return nil
  end

  -- Extract ID from filename (assuming notes are named with their ID)
  local filename = vim.fn.fnamemodify(bufpath, ':t:r')
  return filename
end

function M.rename_label_global()
  -- 1. Identify the defining ^label under cursor
  local old_label = get_label_under_cursor()
  if not old_label then
    vim.notify('No ^label found under cursor', vim.log.levels.WARN)
    return
  end

  local note_id = get_current_note_id()
  if not note_id then
    vim.notify('Could not determine current note ID', vim.log.levels.ERROR)
    return
  end

  -- 2. Prompt user for new label name
  vim.ui.input({ prompt = 'Rename ^' .. old_label .. ' to: ', default = old_label }, function(new_label)
    if not new_label or new_label == '' or new_label == old_label then
      vim.notify('Rename cancelled', vim.log.levels.INFO)
      return
    end

    -- Validate new label name (alphanumeric, underscore, hyphen)
    if not new_label:match('^[%w_%-]+$') then
      vim.notify('Invalid label name. Use only letters, numbers, underscore, and hyphen.', vim.log.levels.ERROR)
      return
    end

    -- 3. Check config for confirmation
    local conf = config.get()
    local should_confirm = conf.refactor and conf.refactor.confirm_global

    local function perform_rename()
      -- 4. Call provider.backrefs to find all notes referencing [[id#^old]]
      local old_ref = '[[' .. note_id .. '#^' .. old_label .. ']]'
      local new_ref = '[[' .. note_id .. '#^' .. new_label .. ']]'

      provider.backrefs(note_id, {}, function(ok, backrefs)
        if not ok then
          vim.notify('Failed to get backrefs: ' .. tostring(backrefs), vim.log.levels.ERROR)
          return
        end

        -- Build edits list for bulk_edit
        local edits = {}
        if backrefs and type(backrefs) == 'table' then
          for _, ref in ipairs(backrefs) do
            if ref.id and ref.id ~= note_id then
              table.insert(edits, {
                id = ref.id,
                find = old_ref,
                replace = new_ref,
              })
            end
          end
        end

        -- 5. Update the defining label in current file
        vim.schedule(function()
          local bufnr = vim.api.nvim_get_current_buf()
          local line_num = vim.api.nvim_win_get_cursor(0)[1] - 1
          local line = vim.api.nvim_buf_get_lines(bufnr, line_num, line_num + 1, false)[1]
          local new_line = line:gsub('%^' .. old_label, '^' .. new_label)
          vim.api.nvim_buf_set_lines(bufnr, line_num, line_num + 1, false, { new_line })

          -- Save current file
          vim.cmd('write')

          -- 6. Apply bulk edits if there are any
          if #edits > 0 then
            vim.notify(
              'Renaming ^' .. old_label .. ' to ^' .. new_label .. ' in ' .. #edits .. ' files...',
              vim.log.levels.INFO
            )
            provider.bulk_edit(edits, function(ok2, result)
              vim.schedule(function()
                if ok2 and result.success then
                  vim.notify(
                    'Successfully renamed ^' .. old_label .. ' to ^' .. new_label .. ' (' .. result.applied .. ' files)',
                    vim.log.levels.INFO
                  )
                else
                  local err_msg = 'Failed to rename in some files'
                  if result.errors and #result.errors > 0 then
                    err_msg = err_msg .. ': ' .. vim.inspect(result.errors)
                  end
                  vim.notify(err_msg, vim.log.levels.ERROR)
                end
              end)
            end)
          else
            vim.notify('Renamed ^' .. old_label .. ' to ^' .. new_label .. ' (no references found)', vim.log.levels.INFO)
          end
        end)
      end)
    end

    if should_confirm then
      vim.ui.select({ 'Yes', 'No' }, {
        prompt = 'Rename ^' .. old_label .. ' to ^' .. new_label .. ' across all references?',
      }, function(choice)
        if choice == 'Yes' then
          perform_rename()
        else
          vim.notify('Rename cancelled', vim.log.levels.INFO)
        end
      end)
    else
      perform_rename()
    end
  end)
end

return M
