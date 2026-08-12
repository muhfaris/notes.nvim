-- lua/notes/mcp/tools/delete.lua
--- MCP tool: notes_delete — delete a note or directory by path.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path

local function handler(args)
	local path = args.path
	if not path or path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path = resolve_path(path)
	if vim.fn.filereadable(abs_path) ~= 1 and vim.fn.isdirectory(abs_path) ~= 1 then
		return encode_checked(encode_json({ error = "not found: " .. path }))
	end

	local ok, err = os.remove(abs_path)
	if not ok then
		return encode_checked(encode_json({ error = "failed to delete: " .. tostring(err) }))
	end

	return encode_checked(encode_json({ success = true, path = abs_path }))
end

return {
	name = "notes_delete",
	description = "Delete a note or directory by path.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the note or directory (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
