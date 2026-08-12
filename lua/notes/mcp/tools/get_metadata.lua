-- lua/notes/mcp/tools/get_metadata.lua
--- MCP tool: notes_get_metadata — get a note's YAML frontmatter metadata.

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

	-- Fallback: basic parse
	local note = parse_note(abs_path)
	if note then
		return encode_checked(encode_json({
			title = note.title,
			date = note.date,
			tags = note.tags,
			summary = note.summary,
		}))
	end

	return encode_checked(encode_json({ error = "failed to parse metadata" }))
end

return {
	name = "notes_get_metadata",
	description = "Get the YAML frontmatter metadata of a note (title, date, tags, summary, custom fields).",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the note (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
