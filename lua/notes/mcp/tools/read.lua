-- lua/notes/mcp/tools/read.lua
--- MCP tool: notes_read — read a note's full content and metadata by path.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path
local parse_note = shared.parse_note

local function handler(args)
	local path = args.path
	if not path or path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path = resolve_path(path)
	if vim.fn.filereadable(abs_path) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. path }))
	end

	local note = parse_note(abs_path)
	if not note then
		return encode_checked(encode_json({ error = "failed to parse note: " .. path }))
	end

	return encode_checked(encode_json({
		path = note.path,
		title = note.title,
		date = note.date,
		tags = note.tags,
		summary = note.summary,
		content = note.body,
	}))
end

return {
	name = "notes_read",
	description = "Read a note's full content and metadata by path. Path can be absolute or relative to notes directory.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the note (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
