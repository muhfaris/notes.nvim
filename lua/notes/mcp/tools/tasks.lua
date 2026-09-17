-- lua/notes/mcp/tools/tasks.lua
--- MCP tool: notes_tasks — scan all notes for open tasks (checklist items,
--- inline TODO/ASK markers, #todo/#tech-debt tags). Wraps the same
--- `notes.shared.tasks` scan that powers the Notes Home kanban board and the
--- Telescope task picker, so an AI agent sees the same task state a human
--- does without re-parsing whole notes' markdown itself.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local notes_dir = shared.notes_dir

local function handler(args)
	local tasks = require("notes.shared.tasks").scan(notes_dir)

	local type_filter = args.type
	local status_filter = args.status
	local limit = args.limit

	local out = {}
	for _, t in ipairs(tasks) do
		local type_ok = not type_filter or type_filter == "" or t.type == type_filter
		local status_ok = not status_filter or status_filter == "" or t.status == status_filter
		if type_ok and status_ok then
			table.insert(out, {
				path = t.path,
				relative_path = t.path:sub(#notes_dir + 2),
				title = t.title,
				lnum = t.lnum,
				text = t.text,
				type = t.type,
				status = t.status,
				detail = t.detail,
				unresolved_link = t.unresolved_link,
			})
			if limit and limit > 0 and #out >= limit then
				break
			end
		end
	end

	return encode_checked(encode_json({ tasks = out, count = #out }))
end

return {
	name = "notes_tasks",
	description = "Scan all notes for open tasks: checklist items (`- [ ]` todo, `- [/]`/`- [~]` doing; done items are excluded), inline TODO/ASK markers, and #todo/#tech-debt tags. Mirrors the Notes Home kanban board. Use the returned `lnum` with notes_toggle_task to change a checklist item's status. A checklist item's `detail` is its linked detail note's path, if any; if the line carries a `[[...]]` link that could not be resolved to a file, `unresolved_link` holds the raw link body instead so a broken link isn't mistaken for 'no link at all'.",
	inputSchema = {
		type = "object",
		properties = {
			type = {
				type = "string",
				description = "Optional filter: 'task' (checklist item), 'todo', 'ask', '#todo', or '#tech-debt'",
			},
			status = {
				type = "string",
				description = "Optional filter for checklist tasks only: 'todo' or 'doing'",
			},
			limit = { type = "number", description = "Optional max results (0 or omitted = unlimited)" },
		},
		required = {},
	},
	handler = handler,
}
