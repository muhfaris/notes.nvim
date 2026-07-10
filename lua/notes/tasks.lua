-- lua/notes/tasks.lua
local M = {}

M.toggle_task = function()
	local line = vim.api.nvim_get_current_line()
	local new_line = nil

	-- Match patterns for list items with checkboxes
	if line:match("^%s*-%s+%[%s%](.*)$") then
		new_line = line:gsub("^(%s*-%s+)%[%s%](.*)$", "%1[x]%2")
	elseif line:match("^%s*-%s+%[x%](.*)$") then
		new_line = line:gsub("^(%s*-%s+)%[x%](.*)$", "%1[ ]%2")
	elseif line:match("^%s*%*%s+%[%s%](.*)$") then
		new_line = line:gsub("^(%s*%*%s+)%[%s%](.*)$", "%1[x]%2")
	elseif line:match("^%s*%*%s+%[x%](.*)$") then
		new_line = line:gsub("^(%s*%*%s+)%[x%](.*)$", "%1[ ]%2")
	end

	if new_line then
		vim.api.nvim_set_current_line(new_line)
	end
end

return M
