-- lua/notes/mcp/tools/toggle_task.lua
--- MCP tool: notes_toggle_task — atomically change a single checklist task's
--- status in place. Rewrites only the target line's checkbox character,
--- mirroring `notes.home`'s `persist_card()`, instead of requiring the
--- caller to read the whole note, hand-edit its markdown, and write the
--- full body back through notes_update (fragile on large weekly notes with
--- many nested tasks).
---
--- A task can be identified by `lnum`, a plain `match` substring, or its
--- `link` (`[[ Parent/Child ]]`). `mark` accepts a raw box (`[x]`, `x`) as
--- well as a status name, which covers the "set_status(link, mark)" case
--- without a separate tool.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local notes_dir = shared.notes_dir

-- Checklist grammar (box map, task-line predicate, box rewriter) comes from
-- notes.shared.tasks so this tool and Home's persist_card cannot drift.
local tasks_shared = require("notes.shared.tasks")

local function resolve_box(args)
	if args.mark ~= nil and args.mark ~= "" then
		local mark = vim.trim(tostring(args.mark))
		local box = mark:match("^%[(.)%]$") or (#mark == 1 and mark) or tasks_shared.status_box(mark)
		if not box or not tasks_shared.KNOWN_BOXES[box] then
			return nil, "mark must be a checkbox glyph (`[ ]`, `[/]`, `[?]`, `[x]`) or one of: todo, doing, waiting, done"
		end
		return box
	end
	if args.status ~= nil and args.status ~= "" then
		local box = tasks_shared.status_box(args.status)
		if not box then
			return nil, "status must be one of: todo, doing, waiting, done"
		end
		return box
	end
	return nil, "provide status or mark"
end

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local box, box_error = resolve_box(args)
	if not box then
		return encode_checked(encode_json({ error = box_error }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	local content = shared.read_content(abs_path)
	if not content then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end

	local current_hash = shared.hash_content(content)
	if not shared.hash_matches(args.expected_hash, current_hash) then
		return encode_checked(encode_json(shared.stale_note_error(abs_path, args.expected_hash, current_hash)))
	end

	local lines = vim.split(content, "\n")
	local hits, lookup_err

	if args.lnum then
		hits = shared.find_task_lines(lines, { lnum = args.lnum })
	elseif args.link then
		hits, lookup_err = shared.find_task_lines(lines, { link = args.link, match = args.match })
	elseif args.match then
		hits, lookup_err = shared.find_task_lines(lines, { match = args.match })
	else
		return encode_checked(encode_json({ error = "provide lnum, match, or link to identify the task line" }))
	end

	if not hits then
		return encode_checked(encode_json(lookup_err or { error = "failed to locate task line" }))
	end
	if #hits == 0 then
		local error = { error = "no checklist task line matched" }
		if args.link then
			local resolved, info = shared.resolve_link(args.link)
			if resolved then
				error.hint = "the link resolves to a note, but no checklist line on " .. abs_path .. " carries it"
			elseif info and (info.suggestions or info.candidates) then
				error.link = args.link
				error.candidates = info.candidates
				error.suggestions = info.suggestions
			end
		end
		return encode_checked(encode_json(error))
	end
	if #hits > 1 then
		return encode_checked(encode_json({
			error = "match is ambiguous, matched " .. #hits .. " task lines; retry with lnum",
			candidates = hits,
		}))
	end

	local target = hits[1]
	local fixed = tasks_shared.set_box(target.line, box)
	if fixed == target.line then
		return encode_checked(encode_json({ error = "failed to update checkbox on line " .. target.lnum }))
	end
	lines[target.lnum] = fixed

	local new_hash = shared.write_content(abs_path, table.concat(lines, "\n"))
	if not new_hash then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end

	local new_status = tasks_shared.box_status(box) or args.status

	-- Best-effort: stamp a linked detail note's own `status` frontmatter too, so
	-- it stays self-describing. Never fails the toggle itself — a missing or
	-- unlinked detail note is normal. Same call Home's persist_card makes, so a
	-- status change reads identically from an AI agent or the dashboard.
	local detail_path, detail_synced = nil, false
	if new_status then
		detail_path, detail_synced = tasks_shared.sync_detail_status(abs_path, fixed, notes_dir, new_status)
	end

	return encode_checked(encode_json({
		success = true,
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		lnum = target.lnum,
		status = new_status,
		mark = box,
		line = fixed,
		hash = new_hash,
		detail_note = detail_path,
		detail_synced = detail_path ~= nil and detail_synced or nil,
	}))
end

return {
	name = "notes_toggle_task",
	description = "Atomically change one checklist task's status ('todo' -> `[ ]`, 'doing' -> `[/]`, 'waiting' -> `[?]`, 'done' -> `[x]`) by rewriting only that line. `mark` accepts a raw glyph (`[x]`, `x`) or a status name, so `{link = '[[ Parent/Child ]]', mark = 'x'}` works as set_status(link, mark). Identify the line with `lnum`, a unique `match` substring, or its `link`. If the task links to a detail note, that note's own `status` frontmatter is stamped to match.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
			status = { type = "string", description = "New status: 'todo', 'doing', 'waiting', or 'done'" },
			mark = { type = "string", description = "Raw checkbox glyph (`[x]`, `x`) or a status name; takes precedence over status" },
			lnum = { type = "number", description = "1-based line number of the checklist task line (from notes_tasks)" },
			match = { type = "string", description = "Substring to uniquely identify the task line" },
			link = { type = "string", description = "Wiki-link on the task line, e.g. `[[ Parent/Child ]]`" },
			expected_hash = {
				type = "string",
				description = "Hash returned by notes_read; rejects the write with code 'stale_note' if the file changed since then",
			},
		},
		required = { "path" },
	},
	handler = handler,
}
