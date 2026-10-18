-- lua/notes/mcp/tools/resolve_link.lua
--- MCP tool: notes_resolve_link — turn a wiki-link body into a concrete note
--- path. Board lines carry `[[ Parent/Child ]]` but no path; this resolves
--- the link through the vault's path/title/detail-note conventions and
--- returns suggestions when it cannot.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

local function handler(args)
	local link = vim.trim(args.link or "")
	if link == "" then
		return encode_checked(encode_json({ error = "link is required" }))
	end

	local abs_path, info = shared.resolve_link(link, { from_path = args.from_path })
	if not abs_path then
		info = info or {}
		if info.ambiguous or (info.suggestions and #info.suggestions > 0) then
			local out = shared.note_lookup_error(link, info)
			out.link = shared.clean_link(link)
			return encode_checked(encode_json(out))
		end
		return encode_checked(encode_json({
			error = "link not found: " .. link,
			link = shared.clean_link(link),
			suggestions = shared.suggest_notes(shared.clean_link(link)),
		}))
	end

	local note = shared.parse_note(abs_path)
	return encode_checked(encode_json({
		success = true,
		link = info.link or shared.clean_link(link),
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		title = note and note.title or vim.fn.fnamemodify(abs_path, ":t:r"),
		date = note and note.date or nil,
		tags = note and note.tags or nil,
		match = info.match,
		hash = shared.file_hash(abs_path),
	}))
end

return {
	name = "notes_resolve_link",
	description = "Resolve a wiki-link to a note path: `[[ Parent/Child ]]`, `[[ Parent/Child|label ]]`, a bare `Parent/Child`, a filename, or a title. Use it on board links before notes_read/notes_update. `from_path` lets a relative link resolve against the containing note's folder. On failure returns `suggestions` or ambiguous `candidates`.",
	inputSchema = {
		type = "object",
		properties = {
			link = { type = "string", description = "Wiki-link body, with or without `[[ ]]`, alias, or anchor" },
			from_path = { type = "string", description = "Optional note containing the link, for relative resolution" },
		},
		required = { "link" },
	},
	handler = handler,
}
