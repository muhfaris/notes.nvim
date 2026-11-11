-- lua/notes/mcp/tools/search.lua
--- MCP tool: notes_search — search notes by title, tags, or summary.
--- Delegates to the notes_list handler with a required query.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local list = require("notes.mcp.tools.list")

local function handler(args)
	local query = args.query
	if not query or query == "" then
		return encode_checked(encode_json({ error = "query is required" }))
	end
	return list.handler(args)
end

return {
	name = "notes_search",
	description = "Find notes by title, tag, or summary (NOT body text; use notes_search_content for that). Use this to locate a note's path before reading or writing it; `names_only=true` returns just {path, relative_path, title}. If you already know the exact title or filename, skip search and pass it straight to notes_read/notes_get_metadata, which resolve titles themselves.",
	inputSchema = {
		type = "object",
		properties = {
			query = { type = "string", description = "Search query" },
			tag = { type = "string", description = "Optional exact tag filter" },
			limit = { type = "number", description = "Optional max results" },
			names_only = { type = "boolean", description = "Return only {path, relative_path, title} per note" },
		},
		required = { "query" },
	},
	handler = handler,
}
