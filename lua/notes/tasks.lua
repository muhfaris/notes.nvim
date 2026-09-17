-- lua/notes/tasks.lua
local M = {}

-- The checklist grammar (which lines are tasks, which glyph means what) is
-- owned by notes.shared.tasks, so this toggle, Home's p/x/b keys and
-- notes_toggle_task cannot disagree about a box.
local tasks_shared = require("notes.shared.tasks")

--- Toggle the checkbox on the cursor line between todo and done.
---
--- Deliberately narrower than notes_toggle_task: only todo <-> done. An
--- in-progress line (`[/]`/`[~]`) and an unrecognized box are left alone — the
--- Home dashboard's `p`/`b` keys and the notes_toggle_task MCP tool own those
--- transitions, so a bare toggle never invents a status.
M.toggle_task = function()
	local line = vim.api.nvim_get_current_line()
	local parsed = tasks_shared.parse_task_line(line)
	if not parsed then
		return
	end
	local status = tasks_shared.box_status(parsed.box)
	if status ~= "todo" and status ~= "done" then
		return
	end
	local next_box = tasks_shared.status_box(status == "todo" and "done" or "todo")
	vim.api.nvim_set_current_line(tasks_shared.set_box(line, next_box))
end

return M
