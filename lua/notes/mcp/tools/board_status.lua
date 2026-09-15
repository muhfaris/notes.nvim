-- lua/notes/mcp/tools/board_status.lua
--- MCP tool: notes_board_status — checklist status counts for one note,
--- grouped by its markdown headings. Answers "what's left on this board"
--- without the caller reading the whole note and counting checkboxes by
--- hand.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end
	local abs_path = resolve_path(args.path)
	if vim.fn.filereadable(abs_path) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. args.path }))
	end

	local f = io.open(abs_path, "r")
	if not f then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end

	local sections = {}
	local order = {}
	local current_heading = "(no heading)"
	local totals = { todo = 0, doing = 0, done = 0 }

	local function bucket(heading)
		if not sections[heading] then
			sections[heading] = { todo = 0, doing = 0, done = 0 }
			table.insert(order, heading)
		end
		return sections[heading]
	end

	for line in f:lines() do
		local heading = line:match("^#+%s+(.*)$")
		if heading then
			current_heading = vim.trim(heading)
		else
			local box = line:match("^%s*[-*]%s*%[(.)%]")
			if box then
				local b = bucket(current_heading)
				if box == " " then
					b.todo = b.todo + 1
					totals.todo = totals.todo + 1
				elseif box == "/" or box == "~" then
					b.doing = b.doing + 1
					totals.doing = totals.doing + 1
				elseif box == "x" or box == "X" then
					b.done = b.done + 1
					totals.done = totals.done + 1
				end
			end
		end
	end
	f:close()

	local out_sections = {}
	for _, heading in ipairs(order) do
		local b = sections[heading]
		table.insert(out_sections, {
			heading = heading,
			todo = b.todo,
			doing = b.doing,
			done = b.done,
			total = b.todo + b.doing + b.done,
		})
	end

	return encode_checked(encode_json({
		path = abs_path,
		totals = totals,
		total = totals.todo + totals.doing + totals.done,
		sections = out_sections,
	}))
end

return {
	name = "notes_board_status",
	description = "Roll up checklist status counts (todo/doing/done) for one note, grouped by its markdown headings. Use instead of notes_read plus manual counting to answer 'what's left' on a weekly/board note.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the board/weekly note (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
