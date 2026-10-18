-- lua/notes/mcp/tools/copy_task.lua
--- MCP tool: notes_copy_task_to_today — copy one checklist item from a board
--- (or any note) into today's daily note, resetting its checkbox. Keeps the
--- source line's text and wiki-link intact, and rewrites only the target
--- file.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local config = shared.config
local notes_dir = shared.notes_dir
local tasks_shared = require("notes.shared.tasks")

local function daily_paths(date)
	local yyyy, mm, dd = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not yyyy then
		return notes_dir .. "/daily_" .. date .. ".md", notes_dir .. "/" .. date .. ".md"
	end
	return string.format("%s/%s/%s/%s/daily.md", notes_dir, yyyy, mm, dd),
		string.format("%s/%s.md", notes_dir, date)
end

--- Open today's daily note, creating it from the configured daily template
--- when neither the nested  .../daily.md nor the legacy YYYY-MM-DD.md exists.
local function ensure_daily(date)
	local nested, legacy = daily_paths(date)
	if vim.fn.filereadable(nested) == 1 then
		return nested, false, nil
	end
	if vim.fn.filereadable(legacy) == 1 then
		return legacy, false, nil
	end

	local dir = vim.fn.fnamemodify(nested, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local template = config.daily_template
	if type(template) ~= "string" or template == "" then
		template = config.template
	end
	if type(template) ~= "string" or template == "" then
		template = [[---
title: "%TITLE%"
date: "%DATE%"
tags: ["daily"]
summary: ""
---

# %TITLE%

## Focus

## Tasks / Notes
]]
	end

	local time = os.date(config.time_format or "%H:%M:%S")
	local body = template
		:gsub("%%TITLE%%", "Daily Note: " .. date)
		:gsub("%%DATE%%", date .. " " .. time)
		:gsub("%%BODY%%", "")
		:gsub("tags:%s*%[%s*%]", 'tags: ["daily"]')

	local hash, err = shared.write_content(nested, body)
	if not hash then
		return nil, false, { error = "could not create today's daily note: " .. tostring(err) }
	end
	return nested, true, nil
end

local function last_link_body(line)
	local body = nil
	for candidate in line:gmatch("%[%[([^%]]+)%]%]") do
		body = candidate
	end
	return body and shared.clean_link(body) or nil
end

--- The detail note's own `parent` frontmatter is the most reliable source of
--- the task's group (`[[ Bug Finding ]]` -> `Bug Finding`).
local function parent_from_detail(line)
	local body = last_link_body(line)
	if not body then
		return nil
	end
	local abs_path = shared.resolve_link(body)
	if not abs_path then
		return nil
	end
	local metadata = require("notes.parser").read_file(abs_path)
	if not metadata or not metadata.parent then
		return nil
	end
	local parent = shared.clean_link(metadata.parent)
	return parent ~= "" and parent or nil
end

--- Fall back to the enclosing checklist line when the source is physically
--- nested under its group.
local function parent_from_context(lines, lnum)
	local parsed = tasks_shared.parse_task_line(lines[lnum])
	if not parsed then
		return nil
	end
	local width = #parsed.indent
	for i = lnum - 1, 1, -1 do
		if lines[i]:match("^#+%s") then
			break
		end
		local candidate = tasks_shared.parse_task_line(lines[i])
		if candidate and #candidate.indent < width then
			return tasks_shared.display_task_text(candidate.rest), tasks_shared.box_status(candidate.box)
		end
	end
	return nil
end

local function source_parent(line, lines, lnum)
	local parent = parent_from_detail(line)
	if parent then
		return parent, nil
	end
	return parent_from_context(lines, lnum)
end

local function source_from_note(path, opts)
	local abs_path, lookup_error = shared.resolve_note_or_error(path)
	if not abs_path then
		return nil, lookup_error
	end
	local content = shared.read_content(abs_path)
	if not content then
		return nil, { error = "failed to read note: " .. abs_path }
	end
	local lines = vim.split(content, "\n")
	local hits, lookup_err = shared.find_task_lines(lines, {
		lnum = opts.lnum,
		match = opts.match,
		link = opts.link,
		heading = opts.heading,
	})
	if not hits then
		return nil, lookup_err
	end
	if #hits == 0 then
		return nil, { error = "no checklist task line matched in " .. abs_path }
	end
	if #hits > 1 then
		return nil, {
			error = "match is ambiguous, matched " .. #hits .. " task lines; retry with lnum",
			candidates = hits,
		}
	end
	local parent_title, parent_status = source_parent(hits[1].line, lines, hits[1].lnum)
	return {
		path = abs_path,
		lnum = hits[1].lnum,
		line = hits[1].line,
		parent_title = parent_title,
		parent_status = parent_status,
	}
end

--- Without from_path, locate the task by its link (or match substring) across
--- the vault. Ambiguity is surfaced instead of silently picking a note.
local function source_from_vault(opts)
	local link = opts.link and shared.clean_link(opts.link) or ""
	local match = opts.match and tostring(opts.match) or ""
	if link == "" and match == "" then
		return nil, { error = "provide from_path, link, or match to identify the task" }
	end

	local hits = {}
	for _, path in ipairs(shared.note_paths()) do
		local content = shared.read_content(path)
		if content then
			local lines = vim.split(content, "\n")
			for lnum, line in ipairs(lines) do
				if tasks_shared.is_task_line(line) then
					local ok = true
					if link ~= "" then
						ok = shared.line_has_link(line, link)
					end
					if ok and match ~= "" then
						ok = line:find(match, 1, true) ~= nil
					end
					if ok then
						local parent_title, parent_status = source_parent(line, lines, lnum)
						table.insert(hits, {
							path = path,
							lnum = lnum,
							line = line,
							parent_title = parent_title,
							parent_status = parent_status,
						})
					end
				end
			end
		end
	end

	if #hits == 0 then
		local error = { error = "no checklist task line matched" }
		if link ~= "" then
			local resolved, info = shared.resolve_link(link)
			if resolved then
				error.hint = "the link resolves to " .. resolved .. ", but no checklist line carries it"
			elseif info then
				error.candidates = info.candidates
				error.suggestions = info.suggestions
			end
		end
		return nil, error
	end
	if #hits > 1 then
		return nil, {
			error = "match is ambiguous, matched " .. #hits .. " task lines in different notes; retry with from_path and lnum",
			candidates = hits,
		}
	end
	return hits[1]
end

local function handler(args)
	local source, source_error
	if args.from_path and args.from_path ~= "" then
		source, source_error = source_from_note(args.from_path, {
			lnum = args.lnum,
			match = args.match,
			link = args.link,
			heading = args.heading,
		})
	else
		source, source_error = source_from_vault({ link = args.link, match = args.match })
	end
	if not source then
		return encode_checked(encode_json(source_error))
	end

	local date = vim.trim(args.date or "") ~= "" and vim.trim(args.date) or os.date(config.date_format or "%Y-%m-%d")
	local target_path
	local created = false
	local implicit_heading = false

	if args.target_path and args.target_path ~= "" then
		local lookup_error
		target_path, lookup_error = shared.resolve_note_or_error(args.target_path)
		if not target_path then
			return encode_checked(encode_json(lookup_error))
		end
	else
		local err
		target_path, created, err = ensure_daily(date)
		if not target_path then
			return encode_checked(encode_json(err))
		end
		implicit_heading = true
	end

	local target_content = shared.read_content(target_path)
	if target_content == nil then
		return encode_checked(encode_json({ error = "failed to read target note: " .. target_path }))
	end
	local current_hash = shared.hash_content(target_content)
	if not shared.hash_matches(args.expected_hash, current_hash) then
		return encode_checked(encode_json(shared.stale_note_error(target_path, args.expected_hash, current_hash)))
	end

	local parsed = tasks_shared.parse_task_line(source.line)
	if not parsed then
		return encode_checked(encode_json({ error = "source line is not a checklist task: " .. source.line }))
	end

	local box
	if args.status == "same" then
		box = parsed.box
	else
		box = tasks_shared.status_box(args.status or "todo")
	end
	if not box then
		return encode_checked(encode_json({ error = "status must be one of: todo, doing, waiting, done, same" }))
	end

	local rest = vim.trim(parsed.rest or "")
	local target_lines = vim.split(target_content, "\n")
	local rendered = "- [" .. box .. "] " .. rest

	local target_heading = args.target_heading
	if implicit_heading and (target_heading == nil or target_heading == "") then
		target_heading = "Tasks / Notes"
	end
	local heading_lnum = nil
	if target_heading and target_heading ~= "" then
		heading_lnum = shared.find_heading(target_lines, target_heading)
		if not heading_lnum and implicit_heading then
			target_heading = nil
		end
	end

	-- Deduplicate inside the destination section only. The same board can
	-- legitimately hold the same task under Saturday and Sunday.
	local explicit_heading_missing = target_heading and target_heading ~= "" and not heading_lnum
	local dedupe_from, dedupe_to = 1, #target_lines
	if heading_lnum then
		dedupe_from = heading_lnum + 1
		dedupe_to = shared.section_end(target_lines, heading_lnum)
	end
	if not explicit_heading_missing then
		for i = dedupe_from, dedupe_to do
			local line = target_lines[i]
			if vim.trim(line) == rendered then
				return encode_checked(encode_json({
					success = true,
					copied = false,
					duplicate = true,
					source_path = source.path,
					source_relative_path = shared.relative_path(source.path),
					source_lnum = source.lnum,
					target_path = target_path,
					target_relative_path = shared.relative_path(target_path),
					target_lnum = i,
					line = line,
					hash = current_hash,
				}))
			end
		end
	end

	local parent_title = source.parent_title
	local parent_lnum = nil
	local parent_created = false
	local placeholder_replaced = false

	local function section_bounds()
		if heading_lnum then
			return heading_lnum + 1, shared.section_end(target_lines, heading_lnum)
		end
		return 1, #target_lines
	end

	-- Consume one empty `- [ ]` placeholder in the destination section: the
	-- copied task should replace it, not be appended beneath it.
	local placeholder = nil
	do
		local from, to = section_bounds()
		for i = from, to do
			local candidate = tasks_shared.parse_task_line(target_lines[i])
			if candidate and vim.trim(candidate.rest or "") == "" then
				placeholder = { lnum = i, indent = candidate.indent or "" }
				table.remove(target_lines, i)
				break
			end
		end
	end

	local lnum, info

	if parent_title and parent_title ~= "" then
		local parent_hits, lookup_err = shared.find_task_lines(target_lines, {
			heading = target_heading,
			match = parent_title,
		})
		if not parent_hits then
			return encode_checked(encode_json(lookup_err or { error = "failed to locate the destination parent" }))
		end
		if #parent_hits > 1 then
			return encode_checked(encode_json({
				error = "destination parent is ambiguous, matched " .. #parent_hits .. " task lines",
				candidates = parent_hits,
			}))
		end

		if #parent_hits == 1 then
			parent_lnum = parent_hits[1].lnum
		else
			parent_lnum = shared.insert_task(target_lines, {
				text = parent_title,
				status = source.parent_status or "todo",
				heading = target_heading,
			})
			if not parent_lnum then
				return encode_checked(encode_json({ error = "failed to create parent task: " .. parent_title }))
			end
			parent_created = true
		end

		lnum, info = shared.insert_task(target_lines, {
			text = rest,
			box = box,
			heading = target_heading,
			parent_lnum = parent_lnum,
		})
		placeholder_replaced = placeholder ~= nil
	elseif placeholder then
		local line = placeholder.indent .. rendered
		lnum = math.min(placeholder.lnum, #target_lines + 1)
		table.insert(target_lines, lnum, line)
		info = { line = line, indent = placeholder.indent }
		placeholder_replaced = true
	else
		lnum, info = shared.insert_task(target_lines, {
			text = rest,
			box = box,
			heading = target_heading,
		})
	end

	if not lnum then
		return encode_checked(encode_json(info))
	end

	local new_hash = shared.write_content(target_path, table.concat(target_lines, "\n"))
	if not new_hash then
		return encode_checked(encode_json({ error = "failed to write target note: " .. target_path }))
	end

	return encode_checked(encode_json({
		success = true,
		copied = true,
		source_path = source.path,
		source_relative_path = shared.relative_path(source.path),
		source_lnum = source.lnum,
		source_line = source.line,
		target_path = target_path,
		target_relative_path = shared.relative_path(target_path),
		target_lnum = lnum,
		target_created = created,
		target_heading = target_heading,
		parent = parent_title ~= "" and parent_title or nil,
		parent_lnum = parent_lnum,
		parent_created = parent_created or nil,
		placeholder_replaced = placeholder_replaced or nil,
		line = info.line,
		hash = new_hash,
	}))
end

return {
	name = "notes_copy_task_to_today",
	description = "Copy one checklist item into today's daily note (created from the daily template if needed), resetting its box to todo while keeping its text and wiki-link. The destination parent group is reused when present and created from the source parent when missing, and the copied task is nested under it. An empty `- [ ]` placeholder in the destination section is replaced rather than left above the copy. Identify the source with `from_path` + `lnum`/`match`/`link`, or with just `link` to search the vault. `status='same'` preserves the source box; `target_path`/`target_heading` override the daily default (use both to copy between sections of the same board). Duplicate detection is scoped to the destination heading, so the same task can exist under different days.",
	inputSchema = {
		type = "object",
		properties = {
			from_path = { type = "string", description = "Source note path, filename, or title (optional when link uniquely identifies the task)" },
			lnum = { type = "number", description = "1-based line number of the source checklist line" },
			match = { type = "string", description = "Substring identifying the source task line" },
			link = { type = "string", description = "Wiki-link carried by the source line, e.g. `[[ Parent/Child ]]`" },
			heading = { type = "string", description = "Optional source heading to scope the search" },
			date = { type = "string", description = "Target daily-note date (default today)" },
			target_path = { type = "string", description = "Copy into this note instead of today's daily note" },
			target_heading = { type = "string", description = "Heading to insert under in the target (default 'Tasks / Notes' for the daily note)" },
			status = { type = "string", description = "New status: 'todo' (default), 'doing', 'waiting', 'done', or 'same' to preserve the source box" },
			expected_hash = {
				type = "string",
				description = "Hash of the target note from notes_read; rejects the write with code 'stale_note' if it changed",
			},
		},
		required = {},
	},
	handler = handler,
}
