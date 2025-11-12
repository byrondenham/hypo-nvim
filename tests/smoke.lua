local M = {}

function M.run()
  local ok, hypo = pcall(require, 'hypo')
  assert(ok and hypo, 'failed to load hypo module')

  local cache = vim.fn.stdpath('cache')
  local vault = vim.fs.joinpath(cache, 'hypo-test-vault')
  vim.fn.mkdir(vault, 'p')

  local cli = require('hypo.adapters.cli')
  local original_run = cli.run
  cli.run = function(args, input, cb)
    local command = args[1]
    if command == 'lint' then
      cb(
        0,
        vim.json.encode({
          {
            id = 'demo-note',
            severity = 'warn',
            message = 'Demo issue',
            line = 1,
            col = 1,
          },
        }),
        ''
      )
    elseif command == 'fmt' then
      cb(0, '', '')
    elseif command == 'new' then
      local path = vim.fs.joinpath(vault, 'demo-note.md')
      cb(0, vim.json.encode({ id = 'demo-note', path = path }), '')
    else
      cb(0, '', '')
    end
  end

  -- Exercise lint path
  require('hypo.features.lint').run()

  -- Exercise session switching
  local session = require('hypo.features.session')
  session.use(vault)
  session.status()

  -- Restore CLI adapter
  cli.run = original_run
end

return M
