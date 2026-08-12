-- lua/notes/mcp/tools/search_content.lua
--- MCP tool: notes_search_content — full-text search inside note content.
--- Uses ripgrep when available, otherwise falls back to a Lua search.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local notes_dir = shared.notes_dir
local scan_notes = shared.scan_notes

local function handler(args)
	local query = args.query
	if not query or query == "" then
		return encode_checked(encode_json({ error = "query is required" }))
	end

	local results = {}
	local escaped_query = vim.pesc(query)

	-- Use grep if available for speed
	local grep_cmd
	if vim.fn.executable("rg") == 1 then
		grep_cmd = { "rg", "-n", "--no-heading", "--color", "never", query, notes_dir }
	elseif vim.fn.executable("grep") == 1 then
		grep_cmd = { "grep", "-rn", "--color", "never", query, notes_dir }
	end

	if grep_cmd then
		local output = vim.fn.system(grep_cmd)
		if vim.v.shell_error == 0 and output ~= "" then
			for line in output:gmatch("[^\n]+") do
				local filepath, lnum, text = line:match("^(.-):(%d+):(.*)$")
				if filepath and lnum then
					local rel = filepath:sub(#notes_dir + 2)
					table.insert(results, {
						path = filepath,
						relative_path = rel,
						line = tonumber(lnum),
						text = text,
					})
				end
			end
		end
	else
		-- Fallback: read all notes and search manually
		local notes = scan_notes()
		for _, note in ipairs(notes) do
			if note.body then
				local idx = 1
				while true do
					local s, e = note.body:find(escaped_query, idx, true)
					if not s then
						break
					end
					-- Get line number
					local line_num = 1
					for _ in note.body:sub(1, s):gmatch("\n") do
						line_num = line_num + 1
					end
					local context_start = math.max(s - 40, 1)
					local context_end = math.min(e + 40, #note.body)
					local snippet = note.body:sub(context_start, context_end):gsub("\n", " ")
					local rel = note.path:sub(#notes_dir + 2)

					table.insert(results, {
						path = note.path,
						relative_path = rel,
						line = line_num,
						text = snippet,
					})

					idx = e + 1
				end
			end
		end
	end

	return encode_checked(encode_json(results))
end

return {
	name = "notes_search_content",
	description = "Full-text search inside note content. Uses ripgrep if available, otherwise falls back to Lua search.",
	inputSchema = {
		type = "object",
		properties = {
			query = { type = "string", description = "Text to search for in note content" },
		},
		required = { "query" },
	},
	handler = handler,
}
