-- lua/notes/utils.lua
local M = {}
local config = require("notes.config").get_config()

-- Function to sanitize the title for use in filename
M.sanitize_title = function(title)
	-- Replace spaces and non-alphanumeric characters with hyphens
	local sanitized = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
	-- Collapse multiple hyphens into a single hyphen
	sanitized = sanitized:gsub("-+", "-")
	-- Trim hyphens from start and end
	return sanitized:gsub("^-+", ""):gsub("-+$", "")
end

M.paste_image = function()
	local image_dir = config.notes_dir .. "/images"
	if vim.fn.isdirectory(image_dir) == 0 then
		vim.fn.mkdir(image_dir, "p")
	end

	local image_name = os.time() .. ".png"
	local image_path = image_dir .. "/" .. image_name

	-- Detect OS & Command
	local cmd = nil
	if vim.fn.has("macunix") == 1 then
		if vim.fn.executable("pngpaste") == 1 then
			cmd = "pngpaste " .. vim.fn.shellescape(image_path)
		else
			cmd = "osascript -e 'write (the clipboard as «class PNGf») to (open for access POSIX file \""
				.. image_path
				.. "\" with write permission)'"
		end
	elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
		cmd =
			"powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Clipboard]::GetImage().Save('"
			.. image_path
			.. "', [System.Drawing.Imaging.ImageFormat]::Png)\""
	else
		-- Linux/Unix
		local wayland_display = os.getenv("WAYLAND_DISPLAY")
		if wayland_display and wayland_display ~= "" and vim.fn.executable("wl-paste") == 1 then
			cmd = "wl-paste -t image/png > " .. vim.fn.shellescape(image_path)
		elseif vim.fn.executable("xclip") == 1 then
			cmd = "xclip -selection clipboard -t image/png -o > " .. vim.fn.shellescape(image_path)
		elseif vim.fn.executable("xsel") == 1 then
			cmd = "xsel --clipboard --output > " .. vim.fn.shellescape(image_path)
		end
	end

	if not cmd then
		vim.notify(
			"No clipboard utility found. Install xclip/wl-paste (Linux), pngpaste (macOS) to paste images.",
			vim.log.levels.ERROR
		)
		return
	end

	-- Run the command
	vim.fn.system(cmd)
	local exit_code = vim.v.shell_error

	-- Verify if file was created and is non-empty (some tools return non-zero but still succeed)
	local success = false
	local file = io.open(image_path, "r")
	if file then
		local size = file:seek("end")
		file:close()
		if size > 0 then
			success = true
		end
	end

	if success then
		-- Insert the markdown relative image link
		local current_file = vim.api.nvim_buf_get_name(0)
		local current_dir = vim.fn.fnamemodify(current_file, ":h")
		current_dir = vim.fn.resolve(current_dir)
		local notes_abs = vim.fn.resolve(config.notes_dir)

		local link_path = "images/" .. image_name
		if current_dir:sub(1, #notes_abs) == notes_abs then
			local sub = current_dir:sub(#notes_abs + 1)
			local depth = 0
			for _ in sub:gmatch("[^/]+") do
				depth = depth + 1
			end
			if depth > 0 then
				local prefix = string.rep("../", depth)
				link_path = prefix .. "images/" .. image_name
			end
		end

		vim.cmd("normal! i![](" .. link_path .. ")")
		vim.notify("Image pasted successfully: " .. link_path, vim.log.levels.INFO)
	else
		-- Clean up empty file if created
		os.remove(image_path)
		vim.notify("Clipboard does not contain an image, or pasting failed.", vim.log.levels.WARN)
	end
end

return M
