-- lua/notes/config.lua
local M = {}

-- Default configuration
M.config = {
	notes_dir = vim.fn.expand("~/.notes"),
	date_format = "%Y-%m-%d",
	time_format = "%H:%M:%S",
	template = [[
# Title: %TITLE%

## Date: %DATE%

## Keywords: %Keywords%

## Summary

## Description

%BODY%

## Conclusion
]],
	keymaps = {},
	key_desc = {
		new_note = "Create new note",
		list_notes = "List notes",
		paste_image = "Paste image",
		find_by_keyword = "Find notes by keyword",
	},
	length_summary = 140,
	length_title = 60,
	fn = {
		new = function()
			require("notes.ui").new_note()
		end,
		list = function()
			require("notes.ui").list_notes()
		end,
		find_by_keyword = function()
			require("notes.ui").find_by_keyword()
		end,
		paste_image = function()
			require("notes.utils").paste_image()
		end,
	},
}

-- Function to set up the plugin
M.setup = function(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	if opts.notes_dir then
		M.config.notes_dir = vim.fn.expand(opts.notes_dir)
	end

	-- Ensure the notes directory exists
	if vim.fn.isdirectory(M.config.notes_dir) == 0 then
		vim.fn.mkdir(M.config.notes_dir, "p")
	end
end

M.get_config = function()
	return M.config
end

return M
