local config = require('hypo.config').get
local M = {}

local function build_args(args)
  local c = config()
  local a = { c.hypo_cmd }
  if c.vault_path then
    table.insert(a, '--vault')
    table.insert(a, c.vault_path)
  end
  for _, x in ipairs(args) do
    table.insert(a, x)
  end
  return a
end

function M.run(args, input, onexit)
  local a = build_args(args)
  local stdout, stderr = {}, {}
  local jobid = vim.fn.jobstart(a, {
    stdin = input and 'pipe' or 'null',
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= '' then
            table.insert(stdout, l)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, l in ipairs(data) do
          if l ~= '' then
            table.insert(stderr, l)
          end
        end
      end
    end,
    on_exit = function(_, code)
      onexit(code, table.concat(stdout, '\n'), table.concat(stderr, '\n'))
    end,
  })
  if input then
    vim.fn.chansend(jobid, input)
    vim.fn.chanclose(jobid, 'stdin')
  end
end

return M
