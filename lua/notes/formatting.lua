-- lua/notes/formatting.lua
local M = {}

-- Generic helper to toggle wrapping of text in Visual or Normal mode.
-- prefix: e.g. "**", "*", "~~", "=="
-- suffix: e.g. "**", "*", "~~", "==" (defaults to prefix if omitted)
local function toggle_wrap(prefix, suffix)
	suffix = suffix or prefix
	local p_len = #prefix
	local s_len = #suffix

	local mode = vim.api.nvim_get_mode().mode
	if mode:match("[vV]") or mode == "\22" then
		-- Exit visual mode synchronously to update the '< and '> marks
		vim.cmd("normal! \27")

		local start_pos = vim.api.nvim_buf_get_mark(0, "<")
		local end_pos = vim.api.nvim_buf_get_mark(0, ">")
		local start_row, start_col = start_pos[1] - 1, start_pos[2]
		local end_row, end_col = end_pos[1] - 1, end_pos[2]

		if start_row < 0 or end_row < 0 then
			return
		end

		local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col + 1, {})
		if #lines == 1 then
			local text = lines[1]
			local new_text
			if #text >= p_len + s_len and text:sub(1, p_len) == prefix and text:sub(-s_len) == suffix then
				-- Unwrap text
				new_text = text:sub(p_len + 1, -(s_len + 1))
			else
				-- Wrap text
				new_text = prefix .. text .. suffix
			end
			vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col + 1, { new_text })
			vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
		end
	else
		-- Normal mode: toggle wrap on word under cursor
		local cursor = vim.api.nvim_win_get_cursor(0)
		local row = cursor[1] - 1
		local col = cursor[2]
		local line = vim.api.nvim_get_current_line()

		local cword = vim.fn.expand("<cword>")
		if cword and cword ~= "" then
			local start_col = col
			while start_col > 0 and line:sub(start_col + 1, start_col + #cword) ~= cword do
				start_col = start_col - 1
			end
			local end_col = start_col + #cword - 1

			local prefix_start = start_col - p_len
			local suffix_end = end_col + s_len
			if
				prefix_start >= 0
				and line:sub(prefix_start + 1, prefix_start + p_len) == prefix
				and line:sub(end_col + 2, suffix_end + 1) == suffix
			then
				-- Unwrap text
				vim.api.nvim_buf_set_text(0, row, prefix_start, row, suffix_end + 1, { cword })
				vim.api.nvim_win_set_cursor(0, { row + 1, prefix_start })
			else
				-- Wrap text
				vim.api.nvim_buf_set_text(0, row, start_col, row, end_col + 1, { prefix .. cword .. suffix })
				vim.api.nvim_win_set_cursor(0, { row + 1, start_col + p_len })
			end
		end
	end
end

M.toggle_bold = function()
	toggle_wrap("**")
end

M.toggle_italic = function()
	toggle_wrap("*")
end

M.toggle_strikethrough = function()
	toggle_wrap("~~")
end

M.toggle_highlight = function()
	toggle_wrap("==")
end

M.insert_link = function()
	local mode = vim.api.nvim_get_mode().mode
	local text = ""
	local start_row, start_col, end_row, end_col

	if mode:match("[vV]") or mode == "\22" then
		vim.cmd("normal! \27")
		local start_pos = vim.api.nvim_buf_get_mark(0, "<")
		local end_pos = vim.api.nvim_buf_get_mark(0, ">")
		start_row, start_col = start_pos[1] - 1, start_pos[2]
		end_row, end_col = end_pos[1] - 1, end_pos[2]

		if start_row >= 0 and end_row >= 0 then
			local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col + 1, {})
			if #lines > 0 then
				text = table.concat(lines, "\n")
			end
		end
	else
		local cursor = vim.api.nvim_win_get_cursor(0)
		start_row = cursor[1] - 1
		local col = cursor[2]
		local line = vim.api.nvim_get_current_line()
		local cword = vim.fn.expand("<cword>")
		if cword and cword ~= "" then
			text = cword
			start_col = col
			while start_col > 0 and line:sub(start_col + 1, start_col + #cword) ~= cword do
				start_col = start_col - 1
			end
			end_row = start_row
			end_col = start_col + #cword - 1
		else
			start_col = col
			end_row = start_row
			end_col = col - 1
		end
	end

	vim.ui.input({ prompt = "URL (optional): " }, function(url)
		if url == nil then
			return -- User pressed Esc / cancelled
		end

		local formatted_link = string.format("[%s](%s)", text, url)
		vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col + 1, { formatted_link })

		if url == "" then
			-- Position cursor between parentheses () for immediate URL typing
			local cursor_col = start_col + #text + 3
			vim.api.nvim_win_set_cursor(0, { start_row + 1, cursor_col })
		end
	end)
end

return M
