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

## Labels: %LABEL%

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
	},
}

-- Function to set up the plugin
M.setup = function(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Ensure the notes directory exists
	if vim.fn.isdirectory(M.config.notes_dir) == 0 then
		vim.fn.mkdir(M.config.notes_dir, "p")
	end
end

return M
