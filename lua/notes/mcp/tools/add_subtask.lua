-- lua/notes/mcp/tools/add_subtask.lua
--- MCP tool: notes_add_subtask — headless equivalent of
--- `notes.subtask.insert_subtask()`. Writes a detail note for a new subtask
--- and inserts a nested, linked checklist line directly beneath an existing
--- parent task line, so an AI agent can build out a board note the same way
--- a human does with <leader>nta instead of hand-editing the whole file
--- through notes_update.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
-- The task-line predicate is owned by notes.shared.tasks, so this tool and the
-- interactive subtask flow agree on what may carry a child.
local tasks_shared = require("notes.shared.tasks")

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end
	local title = vim.trim(args.title or "")
	if title == "" then
		return encode_checked(encode_json({ error = "title is required" }))
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
	local parent_lnum

	if args.parent_lnum then
		parent_lnum = args.parent_lnum
	elseif (args.parent_match and args.parent_match ~= "") or (args.parent_link and args.parent_link ~= "") then
		local found, lookup_err = shared.find_task_lines(lines, {
			match = args.parent_match,
			link = args.parent_link,
			heading = args.heading,
		})
		if not found then
			return encode_checked(encode_json(lookup_err or { error = "failed to locate parent task line" }))
		end
		if #found == 0 then
			local needle = args.parent_match or args.parent_link
			return encode_checked(encode_json({ error = "no task line matched: " .. needle }))
		elseif #found > 1 then
			return encode_checked(encode_json({
				error = "parent_match is ambiguous, matched " .. #found .. " task lines; retry with parent_lnum",
				candidates = found,
			}))
		end
		parent_lnum = found[1].lnum
	else
		return encode_checked(encode_json({
			error = "provide parent_lnum or parent_match to identify the task line to nest under",
		}))
	end

	local parent_line = lines[parent_lnum]
	if not parent_line or not tasks_shared.is_task_line(parent_line) then
		return encode_checked(encode_json({
			error = "line " .. tostring(parent_lnum) .. " is not a checklist task line",
		}))
	end

	local subtask = require("notes.subtask")
	local parent_title = subtask.parent_from_line(parent_line)

	local note_path, note_created = subtask.ensure_detail_note(title, { parent = parent_title, source = abs_path })
	if not note_path then
		return encode_checked(encode_json({ error = "could not write the detail note for: " .. title }))
	end

	local indent = (parent_line:match("^(%s*)") or "") .. "  "
	local child_text = subtask.render_child_line(title, parent_title, indent)
	if not child_text then
		return encode_checked(encode_json({ error = "failed to render checklist line" }))
	end

	table.insert(lines, parent_lnum + 1, child_text)

	local new_hash = shared.write_content(abs_path, table.concat(lines, "\n"))
	if not new_hash then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end

	return encode_checked(encode_json({
		success = true,
		board_path = abs_path,
		relative_path = shared.relative_path(abs_path),
		child_lnum = parent_lnum + 1,
		line = child_text,
		hash = new_hash,
		detail_note = note_path,
		detail_note_created = note_created,
		parent_title = parent_title,
	}))
end

return {
	name = "notes_add_subtask",
	description = "Add a new linked subtask under an existing checklist line: writes a detail note (same shape as notes.subtask.insert_subtask's interactive flow) and inserts a nested `- [ ] [[ parent/title ]]` line directly beneath the parent task. Identify the parent line with `parent_lnum` (from notes_tasks) or a unique `parent_match` substring (optionally scoped with `heading` or `parent_link`). `detail_note_created` is false when a note for that exact title already existed for today and was reused instead of created.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Board/weekly note path, filename, or title (relative or absolute)" },
			title = { type = "string", description = "Subtask title (used as the detail note's title and the checklist line text)" },
			parent_lnum = { type = "number", description = "1-based line number of the parent checklist line (from notes_tasks)" },
			parent_match = { type = "string", description = "Substring to uniquely identify the parent checklist line" },
			parent_link = { type = "string", description = "Wiki-link carried by the parent line, e.g. `[[ Parent/Child ]]`" },
			heading = { type = "string", description = "Optional heading/day to scope the parent search" },
			expected_hash = {
				type = "string",
				description = "Hash returned by notes_read; rejects the write with code 'stale_note' if the file changed since then",
			},
		},
		required = { "path", "title" },
	},
	handler = handler,
}
