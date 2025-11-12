local M = {}
function M.setup(opts)
  require('hypo.config').setup(opts or {})
  require('hypo.commands').register()
  -- Start refresh daemon
  require('hypo.refresh').start()
end
return M
