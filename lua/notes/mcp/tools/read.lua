-- lua/notes/mcp/tools/read.lua
--- MCP tool: notes_read — read a note's full content and metadata by path.
---
--- A full path is not required: a bare filename or title is resolved across
--- the vault, and a miss returns near-miss paths. The returned `hash` is the
--- optimistic-concurrency token notes_update expects as `expected_hash`.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local parse_note = shared.parse_note

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	local content = shared.read_content(abs_path)
	if not content then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end
	local note = parse_note(abs_path, content)
	if not note then
		return encode_checked(encode_json({ error = "failed to parse note: " .. args.path }))
	end

	return encode_checked(encode_json({
		path = note.path,
		relative_path = shared.relative_path(note.path),
		title = note.title,
		date = note.date,
		tags = note.tags,
		summary = note.summary,
		content = note.body,
		hash = shared.hash_content(content),
	}))
end

return {
	name = "notes_read",
	description = "Read a note's full content and metadata. `path` may be a full path, a bare filename (`w2-oct-2026.md`), or a title (`Weekly: w2 oct 2026`) — it is resolved across the vault, and a miss returns `suggestions` with similar paths. The returned `hash` can be passed to writers as `expected_hash` to reject a write when the file changed after this read.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
