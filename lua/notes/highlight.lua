-- lua/notes/highlight.lua
local M = {}

M.toggle_highlight = function()
	require("notes.formatting").toggle_highlight()
end

return M
