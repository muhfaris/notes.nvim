-- lua/notes/mcp/tools/toggle_task.lua
--- MCP tool: notes_toggle_task — atomically flip a single checklist task's
--- status in place. Rewrites only the target line's checkbox character,
--- mirroring `notes.home`'s `persist_card()`, instead of requiring the
--- caller to read the whole note, hand-edit its markdown, and write the
--- full body back through notes_update (fragile on large weekly notes with
--- many nested tasks).

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path
local notes_dir = shared.notes_dir

local STATUS_BOX = { todo = " ", doing = "/", done = "x" }
local TASK_LINE_PATTERN = "^%s*[-*]%s*%[[ xX/~%-]%]"

-- Best-effort: if the task line links to a detail note (notes.subtask's
-- convention), stamp that note's own `status` frontmatter field too, so it
-- stays self-describing without needing the parent board reopened. Never
-- fails the toggle itself — a missing/unlinked detail note is normal.
-- Shared with notes.home's persist_card (notes.shared.tasks.sync_detail_status)
-- so a status change behaves identically from the AI or the Home dashboard.
local function sync_detail_status(board_path, fixed_line, status)
	local ok_tasks, tasks_mod = pcall(require, "notes.shared.tasks")
	if not ok_tasks then
		return nil, false
	end
	return tasks_mod.sync_detail_status(board_path, fixed_line, notes_dir, status)
end

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local box = STATUS_BOX[args.status]
	if not box then
		return encode_checked(encode_json({ error = "status must be one of: todo, doing, done" }))
	end

	local abs_path = resolve_path(args.path)
	if vim.fn.filereadable(abs_path) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. args.path }))
	end

	local f = io.open(abs_path, "r")
	if not f then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end
	local content = f:read("*a")
	f:close()
	local lines = vim.split(content, "\n")

	local target_lnum = args.lnum

	if not target_lnum then
		if not args.match or args.match == "" then
			return encode_checked(encode_json({ error = "provide lnum or match to identify the task line" }))
		end
		local found = {}
		for i, l in ipairs(lines) do
			if l:match(TASK_LINE_PATTERN) and l:find(args.match, 1, true) then
				table.insert(found, { lnum = i, line = l })
			end
		end
		if #found == 0 then
			return encode_checked(encode_json({ error = "no task line matched: " .. args.match }))
		elseif #found > 1 then
			return encode_checked(encode_json({
				error = "match is ambiguous, matched " .. #found .. " task lines; retry with lnum",
				candidates = found,
			}))
		end
		target_lnum = found[1].lnum
	end

	local line = lines[target_lnum]
	if not line or not line:match(TASK_LINE_PATTERN) then
		return encode_checked(encode_json({
			error = "line " .. tostring(target_lnum) .. " is not a checklist task line",
		}))
	end

	local fixed = line:gsub("(%s*[-*]%s*%[)([^%]])(%])", "%1" .. box .. "%3", 1)
	if fixed == line then
		return encode_checked(encode_json({ error = "failed to update checkbox on line " .. target_lnum }))
	end
	lines[target_lnum] = fixed

	local fw = io.open(abs_path, "w")
	if not fw then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end
	fw:write(table.concat(lines, "\n"))
	fw:close()

	local detail_path, detail_synced = sync_detail_status(abs_path, fixed, args.status)

	return encode_checked(encode_json({
		success = true,
		path = abs_path,
		lnum = target_lnum,
		status = args.status,
		line = fixed,
		detail_note = detail_path,
		detail_synced = detail_path ~= nil and detail_synced or nil,
	}))
end

return {
	name = "notes_toggle_task",
	description = "Atomically change one checklist task's status ('todo' -> `[ ]`, 'doing' -> `[/]`, 'done' -> `[x]`) by rewriting only that line, without touching the rest of the note. Identify the line with `lnum` (from notes_tasks) or a unique `match` substring of its text. If the task links to a detail note, that note's own `status` frontmatter is stamped to match.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the note containing the task (relative or absolute)" },
			status = { type = "string", description = "New status: 'todo', 'doing', or 'done'" },
			lnum = { type = "number", description = "1-based line number of the checklist task line (from notes_tasks)" },
			match = { type = "string", description = "Substring to uniquely identify the task line, if lnum is not known" },
		},
		required = { "path", "status" },
	},
	handler = handler,
}
