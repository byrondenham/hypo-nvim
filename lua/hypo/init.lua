local M = {}
function M.setup(opts)
  local config_module = require('hypo.config')
  config_module.setup(opts or {})
  require('hypo.ui.signs').setup()
  require('hypo.features.session').setup()
  local lint_conf = config_module.get().lint or {}
  if lint_conf.auto then
    pcall(function()
      require('hypo.features.lint').toggle_watch()
    end)
  end
  require('hypo.commands').register()
  -- Start refresh daemon
  require('hypo.refresh').start()
end
return M
