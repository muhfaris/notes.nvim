local M = {}
M.setup = function(opts)
	local config = require("notes.config")
	config.setup(opts)

	-- Set up keymaps if provided
	if config.config and config.config.keymaps then
		local keymaps = config.config.keymaps
		for mode, mode_maps in pairs(keymaps) do
			for key, func_name in pairs(mode_maps) do
				-- Fetch the description if available
				local desc = config.config.key_desc[func_name] or "No description from notes.nvim"

				if M[func_name] then
					vim.keymap.set(mode, key, M[func_name], { noremap = true, silent = true, desc = desc })
				else
					vim.notify("Function " .. func_name .. " not found in notes plugin", vim.log.levels.WARN)
				end
			end
		end
	end
end

local function safe_require(module)
	local ok, result = pcall(require, module)
	if not ok then
		error(string.format("Failed to load %s: %s", module, result))
	end
	if type(result) ~= "table" then
		error(string.format("Module %s did not return a table", module))
	end
	return result
end

local ui = safe_require("notes.ui")
local utils = safe_require("notes.utils")

M.new_note = ui.new_note
M.list_notes = ui.list_notes
M.paste_image = utils.paste_image
M.find_by_keyword = ui.find_by_keyword

return M
