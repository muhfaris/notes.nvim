-- lua/notes/mcp/tools/list.lua
--- MCP tool: notes_list — list all notes with metadata, with optional
--- query/tag filters and a result limit.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local scan_notes = shared.scan_notes

local function handler(args)
	local query = (args.query or ""):lower()
	local tag = (args.tag or ""):lower()
	local limit = args.limit or 0

	local notes = scan_notes()

	-- Filter by search query (matches title, tags, summary)
	if query ~= "" then
		local filtered = {}
		for _, note in ipairs(notes) do
			if note.title:lower():find(query, 1, true) or note.summary:lower():find(query, 1, true) then
				table.insert(filtered, note)
			end
			-- Check tags
			for _, t in ipairs(note.tags) do
				if t:lower():find(query, 1, true) then
					table.insert(filtered, note)
					break
				end
			end
		end
		notes = filtered
	end

	-- Filter by specific tag
	if tag ~= "" then
		local filtered = {}
		for _, note in ipairs(notes) do
			for _, t in ipairs(note.tags) do
				if t:lower() == tag then
					table.insert(filtered, note)
					break
				end
			end
		end
		notes = filtered
	end

	-- Sort by date descending
	table.sort(notes, function(a, b)
		return (a.date or "") > (b.date or "")
	end)

	-- Apply limit
	if limit > 0 and #notes > limit then
		local limited = {}
		for i = 1, limit do
			limited[i] = notes[i]
		end
		notes = limited
	end

	-- Strip body from results for listing
	local stripped = {}
	for _, note in ipairs(notes) do
		stripped[#stripped + 1] = {
			path = note.path,
			title = note.title,
			date = note.date,
			tags = note.tags,
			summary = note.summary,
		}
	end

	return encode_checked(encode_json(stripped))
end

return {
	name = "notes_list",
	description = "List all notes with metadata. Filters: query (title/tag/summary), tag (exact match), limit (max results).",
	inputSchema = {
		type = "object",
		properties = {
			query = { type = "string", description = "Optional search query (matches title, tags, summary)" },
			tag = { type = "string", description = "Optional exact tag filter" },
			limit = { type = "number", description = "Optional max results (0 = unlimited)" },
		},
	},
	handler = handler,
}
