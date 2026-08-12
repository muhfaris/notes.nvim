-- lua/notes/mcp/tools/recent.lua
--- MCP tool: notes_recent — most recently opened/edited notes (MRU state
--- written by the interactive plugin, read from shared stdpath data).

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

local function handler(args)
	local limit = args.limit or 10
	local recent = require("notes.recent").read()
	local top = {}
	for i = 1, math.min(limit, #recent) do
		table.insert(top, recent[i])
	end
	return encode_checked(encode_json({
		current = recent[1] and recent[1].path or nil,
		recent = top,
	}))
end

return {
	name = "notes_recent",
	description = "Return the most recently opened/edited notes. `current` is the last-accessed note path; `recent` is newest-first with path, title, date.",
	inputSchema = {
		type = "object",
		properties = {
			limit = { type = "integer", description = "Max notes, default 10", minimum = 1, maximum = 50 },
		},
	},
	handler = handler,
}
