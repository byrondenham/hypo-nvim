local cli = require("hypo.adapters.cli")
local L = require("hypo.util.link")
local M = {}

local function file_exists(path)
	return vim.loop.fs_stat(path) ~= nil
end

local function id_path(vault, id)
	return (vault or "vault") .. "/" .. id .. ".md"
end

function M.create_if_missing_under_cursor()
	local ref = L.under_cursor()
	if not ref or not ref.id then
		return
	end
	local vault = require("hypo.config").get().vault_path
	local path = id_path(vault, ref.id)
	if file_exists(path) then
		return
	end
	local ans = vim.fn.confirm("Create note " .. ref.id .. "?", "&Yes\n&No", 1)
	if ans ~= 1 then
		return
	end
	cli.run({ "new" }, nil, function(code, out, err)
		if code ~= 0 then
			vim.notify("Hypo new failed: " .. (err or out), vim.log.levels.ERROR)
			return
		end
		-- If CLI prints the new ID, but user wants this specific ID:
		-- Optional: support 'hypo new --id <ref.id>' in core; otherwise open the created note.
		vim.cmd("edit " .. vim.fn.fnameescape(path))
	end)
end

return M
