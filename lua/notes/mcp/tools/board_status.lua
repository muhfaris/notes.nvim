-- lua/notes/mcp/tools/board_status.lua
--- MCP tool: notes_board_status — checklist status counts for one note,
--- grouped by its markdown headings. Answers "what's left on this board"
--- without the caller reading the whole note and counting checkboxes by
--- hand.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
-- Checklist grammar (line parse + box -> status) is owned by notes.shared.tasks.
local tasks_shared = require("notes.shared.tasks")

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

	local sections = {}
	local order = {}
	local current_heading = "(no heading)"
	local totals = { todo = 0, doing = 0, waiting = 0, done = 0 }

	local function bucket(heading)
		if not sections[heading] then
			sections[heading] = { todo = 0, doing = 0, waiting = 0, done = 0 }
			table.insert(order, heading)
		end
		return sections[heading]
	end

	for line in (content .. "\n"):gmatch("(.-)\n") do
		local heading = line:match("^#+%s+(.*)$")
		if heading then
			current_heading = vim.trim(heading)
		else
			local parsed = tasks_shared.parse_task_line(line)
			if parsed then
				-- Bucket every checklist line, classifiable or not, so a section
				-- holding only unrecognized boxes still appears with total 0.
				local b = bucket(current_heading)
				local status = tasks_shared.box_status(parsed.box)
				if status then
					b[status] = b[status] + 1
					totals[status] = totals[status] + 1
				end
			end
		end
	end

	local out_sections = {}
	for _, heading in ipairs(order) do
		local b = sections[heading]
		table.insert(out_sections, {
			heading = heading,
			todo = b.todo,
			doing = b.doing,
			waiting = b.waiting,
			done = b.done,
			total = b.todo + b.doing + b.waiting + b.done,
		})
	end

	return encode_checked(encode_json({
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		hash = shared.hash_content(content),
		totals = totals,
		total = totals.todo + totals.doing + totals.waiting + totals.done,
		sections = out_sections,
	}))
end

return {
	name = "notes_board_status",
	description = "Roll up checklist status counts (todo/doing/waiting/done) for one note, grouped by its markdown headings. 'waiting' is the `- [?]` box: asked, waiting on somebody else. Use instead of notes_read plus manual counting to answer 'what's left' on a weekly/board note. `path` may be a full path, filename, or title.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Board/weekly note path, filename, or title (relative or absolute)" },
		},
		required = { "path" },
	},
	handler = handler,
}
