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

-- Checklist grammar (box map, task-line predicate, box rewriter) comes from
-- notes.shared.tasks so this tool and Home's persist_card cannot drift.
local tasks_shared = require("notes.shared.tasks")

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local box = tasks_shared.status_box(args.status)
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
			if tasks_shared.is_task_line(l) and l:find(args.match, 1, true) then
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
	if not line or not tasks_shared.is_task_line(line) then
		return encode_checked(encode_json({
			error = "line " .. tostring(target_lnum) .. " is not a checklist task line",
		}))
	end

	local fixed = tasks_shared.set_box(line, box)
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

	-- Best-effort: stamp a linked detail note's own `status` frontmatter too, so
	-- it stays self-describing. Never fails the toggle itself — a missing or
	-- unlinked detail note is normal. Same call Home's persist_card makes, so a
	-- status change reads identically from an AI agent or the dashboard.
	local detail_path, detail_synced = tasks_shared.sync_detail_status(abs_path, fixed, notes_dir, args.status)

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
