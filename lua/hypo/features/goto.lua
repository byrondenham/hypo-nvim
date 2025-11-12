local cli = require("hypo.adapters.cli")
local L = require("hypo.util.link")
local M = {}

local function open_at(path, start_line)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	if start_line and start_line > 0 then
		vim.api.nvim_win_set_cursor(0, { start_line, 0 })
	end
end

function M.goto_under_cursor()
	local ref = L.under_cursor()
	if not ref then
		vim.notify("Hypo: no [[link]]", vim.log.levels.INFO)
		return
	end
	local anchor = ""
	if ref.anchor_kind and ref.anchor_value then
		anchor = "#" .. (ref.anchor_kind == "block" and "^" or "") .. ref.anchor_value
	end
	cli.run({ "locate", ref.id .. anchor, "--format", "json" }, nil, function(code, out, err)
		if code ~= 0 then
			vim.notify("Hypo locate failed: " .. (err or out), vim.log.levels.INFO)
			return
		end
		local ok, resp = pcall(vim.json.decode, out)
		if not ok then
			return
		end
		open_at(resp.path, resp.lines and resp.lines.start or nil)
	end)
end

return M
