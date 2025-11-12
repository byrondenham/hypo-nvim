local L = {}
-- returns { id, anchor_kind, anchor_value } or nil
function L.parse_brackets(text)
	local inner = text:match("%[%[(.-)%]%]")
	if not inner then
		return nil
	end
	local parts = vim.split(inner, "|", { plain = true })
	local core = parts[1]
	if core:sub(1, 4) == "rel:" and #parts >= 2 then
		core = parts[2]
	end
	local id, anchor = core, nil
	local p = core:find("#", 1, true)
	local ak, av = nil, nil
	if p then
		id = core:sub(1, p - 1)
		anchor = core:sub(p + 1)
		if anchor:sub(1, 1) == "^" then
			ak, av = "block", anchor:sub(2)
		else
			ak, av = "heading", anchor
		end
	end
	return { id = vim.trim(id), anchor_kind = ak, anchor_value = av }
end

function L.under_cursor()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local line = vim.api.nvim_get_current_line()
	local s = line:sub(1, col + 1)
	local open = s:match("()%[%[")
	if not open then
		return nil
	end
	local close = s:find("%]%]", col + 1, false)
	if not close then
		return nil
	end
	local text = line:sub(open, close)
	return L.parse_brackets(text)
end

return L
