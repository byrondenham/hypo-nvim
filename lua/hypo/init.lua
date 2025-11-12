local M = {}
function M.setup(opts)
	require("hypo.config").setup(opts or {})
	require("hypo.commands").register()
end
return M
