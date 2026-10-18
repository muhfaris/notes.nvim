-- lua/notes/mcp/tools/append_info.lua
--- MCP tool: notes_append_info — append one `- Info (<day>): ...` line to a
--- note's summary area without rewriting the file by hand. This is the
--- convention used above a detail note's checklist.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local tasks_shared = require("notes.shared.tasks")

local function info_lines(text, label)
	local lines = {}
	local prefix = "- Info (" .. label .. "): "
	for _, raw in ipairs(vim.split(text, "\n")) do
		local line = vim.trim(raw)
		if line ~= "" then
			if #lines == 0 and line:sub(1, 2) == "- " then
				table.insert(lines, line)
			else
				table.insert(lines, prefix .. line)
			end
		end
	end
	return lines
end

--- Where a summary info line belongs: before the section's first checklist
--- item, else after its last non-blank paragraph. Anchoring to the section end
--- alone is wrong: it lands below the checklist and can sit flush against the
--- next `##` heading.
local function summary_insert_at(lines, heading_lnum)
	local section_end = shared.section_end(lines, heading_lnum)
	local first_task = nil
	local last_content = heading_lnum

	for i = heading_lnum + 1, section_end do
		if tasks_shared.is_task_line(lines[i]) then
			first_task = i
			break
		end
		if vim.trim(lines[i]) ~= "" then
			last_content = i
		end
	end

	if first_task then
		return first_task
	end
	return last_content + 1
end

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end
	local text = vim.trim(args.text or "")
	if text == "" then
		return encode_checked(encode_json({ error = "text is required" }))
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

	local label = vim.trim(args.label or args.day or os.date("%A"))
	if label == "" then
		label = os.date("%A")
	end
	local lines_to_add = info_lines(text, label)
	if #lines_to_add == 0 then
		return encode_checked(encode_json({ error = "text is required" }))
	end

	local lines = vim.split(content, "\n")
	local position = args.position or "before_checklist"
	if position ~= "before_checklist" and position ~= "summary" and position ~= "end" then
		return encode_checked(encode_json({ error = "position must be 'before_checklist', 'summary', or 'end'" }))
	end
	local insert_at = nil
	local blank_before = false
	local blank_after = false

	local function place_in_summary()
		local heading_lnum = shared.find_heading(lines, "Summary")
		if not heading_lnum then
			return false
		end
		insert_at = summary_insert_at(lines, heading_lnum)
		return true
	end

	if position == "end" then
		insert_at = #lines + 1
	elseif position == "summary" then
		place_in_summary()
	else
		for i, line in ipairs(lines) do
			if tasks_shared.is_task_line(line) then
				insert_at = i
				break
			end
		end
		if not insert_at then
			place_in_summary()
		end
	end

	insert_at = insert_at or (#lines + 1)

	-- When the anchor is a checklist line, respect the block above it:
	--   * an existing Info/list block => append after it, before the blank
	--     separator, so consecutive Info lines stay contiguous;
	--   * prose/heading => insert directly above the checklist (after the
	--     blank separator), so the Info line stays attached to the checklist.
	if lines[insert_at] and tasks_shared.is_task_line(lines[insert_at]) then
		local task_at = insert_at
		local block_start = task_at
		while block_start > 1 and vim.trim(lines[block_start - 1]) == "" do
			block_start = block_start - 1
		end
		local last_nonblank = block_start > 1 and lines[block_start - 1] or nil
		if last_nonblank and last_nonblank:match("^%s*[-*]%s") then
			insert_at = block_start
		else
			insert_at = task_at
		end
	end

	local previous = insert_at > 1 and lines[insert_at - 1] or nil
	if
		previous
		and vim.trim(previous) ~= ""
		and not previous:match("^#+%s")
		and not previous:match("^%s*[-*]%s")
	then
		blank_before = true
	end
	if lines[insert_at] and lines[insert_at]:match("^#+%s") then
		blank_after = true
	end

	local lnum = insert_at + (blank_before and 1 or 0)
	if blank_before then
		table.insert(lines, insert_at, "")
	end
	for offset, line in ipairs(lines_to_add) do
		table.insert(lines, lnum + offset - 1, line)
	end
	if blank_after then
		table.insert(lines, lnum + #lines_to_add, "")
	end

	local hash = shared.write_content(abs_path, table.concat(lines, "\n"))
	if not hash then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end

	return encode_checked(encode_json({
		success = true,
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		lnum = lnum,
		lines = lines_to_add,
		label = label,
		position = position,
		hash = hash,
	}))
end

return {
	name = "notes_append_info",
	description = "Append a `- Info (<day>): ...` line to a note without rewriting the rest of the file. By default the line is inserted directly above the first checklist item (the summary convention used by detail notes); `position='summary'` anchors it inside `## Summary` (above that section's checklist, or after its last paragraph) and keeps a blank line before the next heading; `position='end'` appends to the note. Use `label`/`day` to override the weekday name.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
			text = { type = "string", description = "Info text; multi-line text gets one prefixed line per line" },
			label = { type = "string", description = "Day label inside the parentheses; defaults to the current weekday name" },
			day = { type = "string", description = "Alias for label" },
			position = {
				type = "string",
				description = "'before_checklist' (default), 'summary', or 'end'",
			},
			expected_hash = {
				type = "string",
				description = "Hash returned by notes_read; rejects the write with code 'stale_note' if the file changed since then",
			},
		},
		required = { "path", "text" },
	},
	handler = handler,
}
