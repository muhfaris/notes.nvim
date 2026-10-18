-- lua/notes/mcp/tools/get_metadata.lua
--- MCP tool: notes_get_metadata — get a note's YAML frontmatter metadata,
--- including custom fields such as `parent` and `source_note`.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	local metadata = require("notes.parser").read_file(abs_path)
	if not metadata then
		return encode_checked(encode_json({ error = "failed to parse metadata" }))
	end

	local out = shared.normalize_metadata(metadata)
	out.path = abs_path
	out.relative_path = shared.relative_path(abs_path)
	out.hash = shared.file_hash(abs_path)
	return encode_checked(encode_json(out))
end

return {
	name = "notes_get_metadata",
	description = "Get a note's YAML frontmatter metadata (title, date, tags, summary, and custom fields such as `parent`/`source_note`). `path` may be a full path, filename, or title.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
