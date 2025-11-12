-- features/meta.lua
-- View / edit metadata (frontmatter) for current note
local M = {}
local provider = require('hypo.provider')

local function buf_name_for(id)
  return 'HypoMeta:' .. id
end

local function parse_simple(lines)
  local t = {}
  local curk = nil
  for _, l in ipairs(lines) do
    local s = vim.trim(l)
    if s ~= '' then
      local k, v = s:match('^([^:]+):%s*(.*)$')
      if k then
        k = vim.trim(k)
        v = vim.trim(v)
        if v == '' then
          -- start list
          t[k] = {}
          curk = k
        else
          -- scalar
          t[k] = v
          curk = nil
        end
      else
        local dash, val = s:match('^%-+%s*(.*)$')
        if dash and curk then
          table.insert(t[curk], val)
        end
      end
    end
  end
  return t
end

function M.view_current()
  local id = require('hypo.util.link').current_id()
  if not id then
    vim.notify('No current note id', vim.log.levels.WARN)
    return
  end
  provider.meta_get(id, nil, function(ok, meta)
    if not ok then
      vim.notify('meta_get failed: ' .. tostring(meta), vim.log.levels.ERROR)
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buf_name_for(id))
    local lines = {}
    for k, v in pairs(meta or {}) do
      if type(v) == 'table' then
        table.insert(lines, k .. ':')
        for _, it in ipairs(v) do
          table.insert(lines, '- ' .. tostring(it))
        end
      else
        table.insert(lines, k .. ': ' .. tostring(v))
      end
    end
    if #lines == 0 then
      table.insert(lines, '# no metadata')
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'yaml')
    vim.api.nvim_open_win(
      buf,
      true,
      { relative = 'editor', row = 5, col = 10, width = 60, height = 20, style = 'minimal', border = 'rounded' }
    )
  end)
end

function M.edit_current()
  local id = require('hypo.util.link').current_id()
  if not id then
    vim.notify('No current note id', vim.log.levels.WARN)
    return
  end
  provider.meta_get(id, nil, function(ok, meta)
    if not ok then
      vim.notify('meta_get failed: ' .. tostring(meta), vim.log.levels.ERROR)
      return
    end
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, buf_name_for(id))
    local lines = {}
    for k, v in pairs(meta or {}) do
      if type(v) == 'table' then
        table.insert(lines, k .. ':')
        for _, it in ipairs(v) do
          table.insert(lines, '- ' .. tostring(it))
        end
      else
        table.insert(lines, k .. ': ' .. tostring(v))
      end
    end
    if #lines == 0 then
      table.insert(lines, '# empty meta')
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'yaml')

    -- write handler: on BufWriteCmd or BufWritePost, parse and call meta_set
    vim.api.nvim_buf_set_keymap(buf, 'n', '<leader>w', '', {
      nowait = true,
      noremap = true,
      callback = function()
        local lns = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local parsed = parse_simple(lns)
        provider.meta_set(id, parsed, function(ok2, res)
          if ok2 then
            vim.notify('Metadata updated', vim.log.levels.INFO)
            -- close buffer
            vim.api.nvim_buf_delete(buf, { force = true })
          else
            vim.notify('meta_set failed: ' .. tostring(res), vim.log.levels.ERROR)
          end
        end)
      end,
      desc = 'Save Hypo meta',
    })
    vim.api.nvim_open_win(
      buf,
      true,
      { relative = 'editor', row = 5, col = 10, width = 60, height = 20, style = 'minimal', border = 'rounded' }
    )
  end)
end

return M
