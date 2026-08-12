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
	description = "Search notes by title, tags, or summary. Returns matching notes with metadata.",
	inputSchema = {
		type = "object",
		properties = {
			query = { type = "string", description = "Search query" },
			tag = { type = "string", description = "Optional exact tag filter" },
			limit = { type = "number", description = "Optional max results" },
		},
		required = { "query" },
	},
	handler = handler,
}
