-- lua/notes/highlight.lua
local M = {}

M.toggle_highlight = function()
	local mode = vim.api.nvim_get_mode().mode
	if mode:match("[vV]") or mode == "\22" then
		-- Visual / Visual Block mode: wrap selection
		-- Exit visual mode synchronously to update the '< and '> marks
		vim.cmd("normal! \27")

		local start_pos = vim.api.nvim_buf_get_mark(0, "<")
		local end_pos = vim.api.nvim_buf_get_mark(0, ">")
		local start_row, start_col = start_pos[1] - 1, start_pos[2]
		local end_row, end_col = end_pos[1] - 1, end_pos[2]

		-- Handle case where marks are invalid
		if start_row < 0 or end_row < 0 then
			return
		end

		-- Retrieve selected text
		local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col + 1, {})
		if #lines == 1 then
			local text = lines[1]
			local new_text
			if text:match("^==.*==$") then
				-- Remove highlight
				new_text = text:sub(3, -3)
			else
				-- Add highlight
				new_text = "==" .. text .. "=="
			end
			vim.api.nvim_buf_set_text(0, start_row, start_col, end_row, end_col + 1, { new_text })
			vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
		end
	else
		-- Normal mode: wrap word under cursor
		local cursor = vim.api.nvim_win_get_cursor(0)
		local row = cursor[1] - 1
		local col = cursor[2]
		local line = vim.api.nvim_get_current_line()

		local cword = vim.fn.expand("<cword>")
		if cword and cword ~= "" then
			-- Find the start of cword on current line around cursor col
			local start_col = col
			while start_col > 0 and line:sub(start_col + 1, start_col + #cword) ~= cword do
				start_col = start_col - 1
			end
			local end_col = start_col + #cword - 1

			-- Check if it is already wrapped in ==
			local prefix_start = start_col - 2
			local suffix_end = end_col + 2
			if prefix_start >= 0 and line:sub(prefix_start + 1, prefix_start + 2) == "==" and line:sub(end_col + 2, end_col + 3) == "==" then
				-- Remove highlight
				vim.api.nvim_buf_set_text(0, row, prefix_start, row, suffix_end + 1, { cword })
				vim.api.nvim_win_set_cursor(0, { row + 1, prefix_start })
			else
				-- Add highlight
				vim.api.nvim_buf_set_text(0, row, start_col, row, end_col + 1, { "==" .. cword .. "==" })
				vim.api.nvim_win_set_cursor(0, { row + 1, start_col + 2 })
			end
		end
	end
end

return M
