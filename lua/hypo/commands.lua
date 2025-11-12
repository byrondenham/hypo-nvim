local M = {}
function M.register()
	vim.api.nvim_create_user_command("HypoGoto", function()
		require("hypo.features.goto").goto_under_cursor()
	end, {})
	vim.api.nvim_create_user_command("HypoPreview", function()
		require("hypo.features.preview").preview_under_cursor()
	end, {})
	vim.api.nvim_create_user_command("HypoInsertLink", function()
		require("hypo.features.completion").insert_link()
	end, {})
	vim.api.nvim_create_user_command("HypoBacklinks", function()
		require("hypo.features.backlinks").open_panel()
	end, {})

	-- suggested defaults; let users override
	vim.keymap.set("n", "gf", "<cmd>HypoGoto<cr>", { desc = "Hypo goto link" })
	vim.keymap.set("n", "gp", "<cmd>HypoPreview<cr>", { desc = "Hypo preview link" })
	vim.keymap.set("i", "<C-l>", "<cmd>HypoInsertLink<cr>", { desc = "Hypo insert [[id]]" })
	vim.keymap.set("n", "<leader>hb", "<cmd>HypoBacklinks<cr>", { desc = "Hypo backlinks" })
end

return M
