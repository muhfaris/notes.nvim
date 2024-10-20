local M = {}
local config = require("notes.config").config

-- Function to sanitize the title for use in filename
M.sanitize_title = function(title)
	-- Replace spaces and non-alphanumeric characters with hyphens
	local sanitized = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
	-- Trim hyphens from start and end
	return sanitized:gsub("^-+", ""):gsub("-+$", "")
end

M.paste_image = function()
	local image_dir = config.notes_dir .. "/images"
	if vim.fn.isdirectory(image_dir) == 0 then
		vim.fn.mkdir(image_dir, "p")
	end

	local image_path = image_dir .. "/" .. os.time() .. ".png"
	vim.fn.system("xclip -selection clipboard -t image/png -o > " .. image_path)
	vim.cmd("normal! i![](" .. image_path .. ")")
end

return M
