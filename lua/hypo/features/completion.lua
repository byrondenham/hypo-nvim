local cli = require('hypo.adapters.cli')
local M = {}

local function fetch_ids(cb)
  cli.run({ 'ls', '--with-titles' }, nil, function(code, out, _)
    if code ~= 0 then
      cb({})
      return
    end
    local items = {}
    for line in out:gmatch('[^\r\n]+') do
      local id, title = line:match('([a-f0-9]+)%s+(.*)')
      table.insert(items, { word = id, menu = title or '' })
    end
    cb(items)
  end)
end

function M.insert_link()
  fetch_ids(function(items)
    if #items == 0 then
      vim.notify('Hypo: no notes', vim.log.levels.INFO)
      return
    end
    local choices = { 'Pick note ID:' }
    for i, it in ipairs(items) do
      choices[#choices + 1] = string.format('%s\t%s', it.word, it.menu)
    end
    local idx = vim.fn.inputlist(choices)
    if idx <= 0 then
      return
    end
    local id = items[idx].word
    vim.api.nvim_put({ '[[' .. id .. ']]' }, 'c', true, true)
  end)
end

return M
