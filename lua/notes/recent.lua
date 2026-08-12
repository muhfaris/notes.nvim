-- lua/notes/recent.lua
--- Recent-notes MRU state shared between the interactive plugin and the MCP server.
--- persist() is called from autocommands in the live session; read() is used
--- by the MCP `notes_recent` tool in the headless instance.
local M = {}

local config = require("notes.config").get_config()

local state_path = vim.fn.stdpath("data") .. "/notes-recent.json"
local MAX = 50

local function notes_abs()
	return vim.fn.fnamemodify(vim.fn.expand(config.notes_dir), ":p"):gsub("/+$", "")
end

--- Push a note path onto the MRU list and persist. Call on BufRead/BufWritePost.
M.persist = function(buf)
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" or vim.fn.filereadable(path) ~= 1 then
		return
	end

	local dir = notes_abs()
	if path:sub(1, #dir) ~= dir then
		return -- not a notes file; ignore
	end

	local mtime = vim.fn.getftime(path)
	local entries = M.read()

	-- Remove existing entry with the same path, then prepend.
	for i = #entries, 1, -1 do
		if entries[i].path == path then
			table.remove(entries, i)
		end
	end
	table.insert(entries, 1, {
		path = path,
		title = vim.fn.fnamemodify(path, ":t:r"),
		mtime = mtime,
		date = os.date("%Y-%m-%d %H:%M:%S", mtime),
	})

	-- Cap length.
	while #entries > MAX do
		table.remove(entries)
	end

	local f = io.open(state_path, "w")
	if f then
		f:write(vim.json.encode(entries))
		f:close()
	end
end

--- Read the MRU list. Returns {} if none/corrupted.
M.read = function()
	local f = io.open(state_path, "r")
	if not f then
		return {}
	end
	local content = f:read("*all")
	f:close()
	if not content or content == "" then
		return {}
	end
	local ok, entries = pcall(vim.json.decode, content)
	if not ok or type(entries) ~= "table" then
		return {}
	end
	return entries
end

return M
