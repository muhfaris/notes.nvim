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
			local hit = note.title:lower():find(query, 1, true) or note.summary:lower():find(query, 1, true)
			if not hit then
				for _, t in ipairs(note.tags) do
					if t:lower():find(query, 1, true) then
						hit = true
						break
					end
				end
			end
			if hit then
				table.insert(filtered, note)
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

	if args.names_only then
		local names = {}
		for _, note in ipairs(notes) do
			names[#names + 1] = {
				path = note.path,
				relative_path = shared.relative_path(note.path),
				title = note.title,
			}
		end
		return encode_checked(encode_json(names))
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
	description = "List notes with metadata (path, title, date, tags, summary), newest first. Use to browse or filter by tag. To find a note by name or topic, prefer notes_search; to find text inside note bodies, use notes_search_content. `names_only=true` returns just {path, relative_path, title}.",
	inputSchema = {
		type = "object",
		properties = {
			query = { type = "string", description = "Optional search query (matches title, tags, summary)" },
			tag = { type = "string", description = "Optional exact tag filter" },
			limit = { type = "number", description = "Optional max results (0 = unlimited)" },
			names_only = { type = "boolean", description = "Return only {path, relative_path, title} per note" },
		},
	},
	handler = handler,
}
