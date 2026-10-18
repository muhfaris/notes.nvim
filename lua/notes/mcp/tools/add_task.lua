-- lua/notes/mcp/tools/add_task.lua
--- MCP tool: notes_add_task — insert one checklist line into a board note.
---
--- This is the incremental counterpart to notes_update: it locates a day
--- heading and/or a parent task, inserts a single `- [ ] ...` line, and
--- leaves every other byte of the file alone. `link` makes the line point at
--- a detail note (`- [ ] [[ Parent/Child ]]`).

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

--- Insert a task into an already-resolved note path.
--- @param abs_path string Absolute note path.
--- @param opts table { text, link, status, heading, parent_lnum, parent_match, parent_link, expected_hash }
--- @return table|nil result, table|nil error
local function insert(abs_path, opts)
	opts = opts or {}
	local content = shared.read_content(abs_path)
	if not content then
		return nil, { error = "failed to read note: " .. abs_path }
	end

	local current_hash = shared.hash_content(content)
	if not shared.hash_matches(opts.expected_hash, current_hash) then
		return nil, shared.stale_note_error(abs_path, opts.expected_hash, current_hash)
	end

	local lines = vim.split(content, "\n")
	local lnum, info = shared.insert_task(lines, {
		text = opts.text,
		link = opts.link,
		status = opts.status,
		heading = opts.heading,
		parent_lnum = opts.parent_lnum,
		parent_match = opts.parent_match,
		parent_link = opts.parent_link,
	})
	if not lnum then
		return nil, info
	end

	local hash = shared.write_content(abs_path, table.concat(lines, "\n"))
	if not hash then
		return nil, { error = "failed to write note: " .. abs_path }
	end

	return {
		success = true,
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		lnum = lnum,
		line = info.line,
		hash = hash,
		parent = info.parent,
	}
end

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local text = vim.trim(args.text or args.title or "")
	local link = vim.trim(args.link or "")
	if text == "" and link == "" then
		return encode_checked(encode_json({ error = "text or link is required" }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	local result, err = insert(abs_path, {
		text = text,
		link = link,
		status = args.status or "todo",
		heading = args.heading or args.day,
		parent_lnum = args.parent_lnum,
		parent_match = args.parent_match or args.parent,
		parent_link = args.parent_link,
		expected_hash = args.expected_hash,
	})
	if not result then
		return encode_checked(encode_json(err))
	end
	return encode_checked(encode_json(result))
end

return {
	name = "notes_add_task",
	description = "Insert one checklist line into a board note under an optional day `heading` and/or `parent` task, without replacing the rest of the file. Supply `text`, `link` (rendered as `- [ ] [[ link ]]`), or both. `parent` is a substring of the parent task line; `heading` scopes the search (e.g. `Tuesday`). Returns the new line and its `lnum`.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Board note path, filename, or title (relative or absolute)" },
			text = { type = "string", description = "Task text (optional when link is given)" },
			link = { type = "string", description = "Wiki-link body or path to attach to the line, e.g. `Parent/Child` or `[[ Parent/Child ]]`" },
			status = { type = "string", description = "Checkbox status: 'todo' (default), 'doing', 'waiting', or 'done'" },
			heading = { type = "string", description = "Day/section heading to insert under, e.g. 'Tuesday' or '### Tuesday'" },
			day = { type = "string", description = "Alias for heading (a day name)" },
			parent_lnum = { type = "number", description = "1-based line number of the parent checklist line" },
			parent = { type = "string", description = "Substring identifying the parent task line" },
			parent_match = { type = "string", description = "Alias for parent (substring identifying the parent task line)" },
			parent_link = { type = "string", description = "Wiki-link carried by the parent line, if identifying it by link" },
			expected_hash = {
				type = "string",
				description = "Hash returned by notes_read; rejects the write with code 'stale_note' if the file changed since then",
			},
		},
		required = { "path" },
	},
	handler = handler,
	insert = insert,
}
