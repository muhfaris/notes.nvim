-- lua/notes/mcp/tools/create.lua
--- MCP tool: notes_create — create a new note with frontmatter from an
--- optional named template; resolves filename collisions automatically.
---
--- With `parent`, the note uses the task-detail convention instead:
--- frontmatter carries `parent`/`source_note`, and the file lands at
--- tasks/YYYY/MM/YYYY-MM-DD-<slug>.md. `board_path` additionally inserts the
--- matching checklist line into the board in one call.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local config = shared.config
local notes_dir = shared.notes_dir

local function slugify(title)
	local sanitized = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
	return (sanitized:gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", ""))
end

local function normalize_tags(tags)
	local out = {}
	if type(tags) == "table" then
		for _, tag in ipairs(tags) do
			table.insert(out, tostring(tag))
		end
	end
	return out
end

local function tags_literal(tags)
	if #tags == 0 then
		return "[]"
	end
	local quoted = {}
	for _, tag in ipairs(tags) do
		table.insert(quoted, '"' .. tag:gsub('"', '\\"') .. '"')
	end
	return "[" .. table.concat(quoted, ", ") .. "]"
end

local function resolve_template(name)
	local cfg_templates = config.templates or {}
	local resolved, template_dir

	if name == "default" then
		resolved = config.template
	elseif cfg_templates[name] ~= nil then
		local template = cfg_templates[name]
		if type(template) == "string" then
			resolved = template
		elseif type(template) == "table" then
			local cfg_mod = require("notes.config")
			local builtin = cfg_mod._builtin_templates and cfg_mod._builtin_templates[name]
			resolved = template.content or builtin
			if template.directory then
				template_dir = notes_dir .. "/" .. template.directory:gsub("^/*", ""):gsub("/*$", "")
			end
		end
	elseif name == "daily" and not cfg_templates.daily then
		local daily = config.daily_template
		if type(daily) == "table" then
			resolved = daily.content or require("notes.config")._builtin_daily_template
		else
			resolved = daily
		end
	else
		local file_path = notes_dir .. "/templates/" .. name .. ".md"
		if vim.fn.filereadable(file_path) == 1 then
			local f = io.open(file_path, "r")
			if f then
				resolved = f:read("*all")
				f:close()
			end
		end
	end

	return resolved, template_dir
end

local function template_names()
	local names = { "default" }
	for name, _ in pairs(config.templates or {}) do
		if type(name) == "string" then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

local function handler(args)
	local title = vim.trim(args.title or "")
	if title == "" then
		return encode_checked(encode_json({ error = "title is required" }))
	end

	local sanitized = slugify(title)
	if sanitized == "" then
		return encode_checked(encode_json({ error = "title has no usable filename characters" }))
	end

	local date = vim.trim(args.date or "")
	if date == "" then
		date = os.date(config.date_format or "%Y-%m-%d") .. " " .. os.date(config.time_format or "%H:%M:%S")
	end
	local date_stamp = date:match("^(%d%d%d%d%-%d%d%-%d%d)") or os.date(config.date_format or "%Y-%m-%d")
	local parent = vim.trim(args.parent or "")
	local source_note = vim.trim(args.source_note or "")
	local yyyy, mm, dd = date_stamp:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")

	local board_abs = nil
	if args.board_path and args.board_path ~= "" then
		local lookup_error
		board_abs, lookup_error = shared.resolve_note_or_error(args.board_path)
		if not board_abs then
			return encode_checked(encode_json(lookup_error))
		end
		if source_note == "" then
			source_note = shared.relative_path(board_abs) or ""
		end
	end

	local content
	local filename
	local target_dir
	local tags

	if parent ~= "" then
		-- Task-detail convention (same shape notes.subtask writes).
		tags = args.tags ~= nil and normalize_tags(args.tags) or { "task" }
		if args.directory then
			target_dir = notes_dir .. "/" .. args.directory:gsub("^/*", ""):gsub("/*$", "")
		elseif yyyy and mm then
			target_dir = notes_dir .. "/tasks/" .. yyyy .. "/" .. mm
		else
			target_dir = notes_dir .. "/tasks"
		end

		if not args.directory and yyyy and mm and dd then
			filename = string.format("%s-%s-%s-%s.md", yyyy, mm, dd, sanitized)
		else
			filename = sanitized .. ".md"
		end

		local metadata = {
			title = title,
			date = date,
			tags = tags,
			summary = "",
			parent = "[[ " .. parent .. " ]]",
		}
		if source_note ~= "" then
			metadata.source_note = source_note
		end

		local parser = require("notes.parser")
		local extra = args.content or ""
		local body
		if vim.trim(extra) ~= "" then
			-- The caller's markdown is the body. Wrapping it in the default
			-- "# title / ## Notes" skeleton duplicates the caller's own H1.
			body = extra
			if body:sub(-1) ~= "\n" then
				body = body .. "\n"
			end
		else
			body = "# " .. title .. "\n\n## Notes\n"
		end

		content = parser.format_frontmatter(metadata) .. "\n" .. body
	else
		tags = normalize_tags(args.tags)
		local tags_str = tags_literal(tags)
		local template = config.template

		if args.template and args.template ~= "" then
			local resolved, template_dir = resolve_template(args.template)
			if resolved == nil or resolved == "" then
				return encode_checked(encode_json({
					error = "unknown template: "
						.. args.template
						.. ". Available templates: "
						.. table.concat(template_names(), ", "),
				}))
			end
			template = resolved
			if template_dir then
				target_dir = template_dir
			end
		end

		local body = (args.content or ""):gsub("^%s*$", "")
		local expanded = template
			:gsub("%%TITLE%%", function()
				return title
			end)
			:gsub("%%DATE%%", function()
				return date
			end)
			:gsub("%%TAGS%%", function()
				return tags_str
			end)
		if vim.trim(args.content or "") == "" then
			expanded = expanded:gsub("%%BODY%%", function()
				return body
			end)
		end

		if vim.trim(args.content or "") ~= "" then
			-- Content is the body verbatim. Keep the template's frontmatter
			-- (title/tags/custom fields) but drop its skeleton so a caller's
			-- own H1 doesn't follow an empty `## Description`/`## Notes`.
			local parser = require("notes.parser")
			local metadata
			if expanded:match("^%-%-%-\n") then
				metadata = parser.parse(expanded, sanitized .. ".md")
			end
			if not metadata then
				metadata = { title = title, date = date, tags = tags, summary = "" }
			end
			if not metadata.title or metadata.title == "" then
				metadata.title = title
			end
			if not metadata.date or metadata.date == "" then
				metadata.date = date
			end
			if type(metadata.tags) ~= "table" or #metadata.tags == 0 then
				metadata.tags = tags
			end

			local verbatim = args.content
			if verbatim:sub(-1) ~= "\n" then
				verbatim = verbatim .. "\n"
			end
			content = parser.format_frontmatter(metadata) .. "\n" .. verbatim
		else
			content = expanded
		end

		if args.directory then
			target_dir = notes_dir .. "/" .. args.directory:gsub("^/*", ""):gsub("/*$", "")
		end
		target_dir = target_dir or notes_dir
		filename = sanitized .. ".md"
	end

	if vim.fn.isdirectory(target_dir) == 0 then
		vim.fn.mkdir(target_dir, "p")
	end

	local filepath = target_dir .. "/" .. filename
	if vim.fn.filereadable(filepath) == 1 then
		local stem = filename:gsub("%.md$", "")
		local counter = 1
		while vim.fn.filereadable(filepath) == 1 do
			filename = string.format("%s_%d.md", stem, counter)
			filepath = target_dir .. "/" .. filename
			counter = counter + 1
		end
	end

	local hash = shared.write_content(filepath, content)
	if not hash then
		return encode_checked(encode_json({ error = "failed to create note at: " .. filepath }))
	end

	local out = {
		success = true,
		path = filepath,
		relative_path = shared.relative_path(filepath),
		title = title,
		filename = filename,
		date = date,
		tags = tags,
		hash = hash,
	}
	if parent ~= "" then
		out.parent = parent
	end
	if source_note ~= "" then
		out.source_note = source_note
	end

	if board_abs then
		local link_body = parent ~= "" and (parent .. "/" .. title) or title
		local add_task = require("notes.mcp.tools.add_task")
		local board_result, board_error = add_task.insert(board_abs, {
			text = args.board_text or "",
			link = link_body,
			status = args.board_status or "todo",
			heading = args.heading,
			parent_lnum = args.board_parent_lnum or args.parent_lnum,
			parent_match = args.board_parent_match or args.parent_match or (parent ~= "" and parent or nil),
			parent_link = args.board_parent_link,
		})
		if board_result then
			out.board_path = board_result.path
			out.board_relative_path = board_result.relative_path
			out.board_lnum = board_result.lnum
			out.board_line = board_result.line
			out.board_hash = board_result.hash
		else
			out.board_error = board_error and board_error.error or "failed to add the board line"
			out.board_error_detail = board_error
		end
	end

	return encode_checked(encode_json(out))
end

return {
	name = "notes_create",
	description = "Create a new note with frontmatter, from an optional named template. When `content` is supplied it becomes the note body verbatim; the template supplies only frontmatter (so no extra H1/empty sections are added). With `parent`, it creates a task-detail note using the plugin's convention (frontmatter title/date/tags/parent/source_note, path tasks/YYYY/MM/YYYY-MM-DD-<slug>.md). With `board_path`, it also inserts the matching `- [ ] [[ parent/title ]]` line into that board under `heading`/`parent_match`; an exact parent label wins over child links containing it. Returns the note path, hash, and board line when inserted.",
	inputSchema = {
		type = "object",
		properties = {
			title = { type = "string", description = "Note title (used for filename, frontmatter, and board link)" },
			content = { type = "string", description = "Optional body content (markdown), used verbatim; template frontmatter is retained but its body skeleton is not" },
			tags = { type = "array", items = { type = "string" }, description = "Optional list of tags" },
			directory = {
				type = "string",
				description = "Optional subdirectory under notes (e.g. 'work/meetings'). With parent, defaults to tasks/YYYY/MM",
			},
			template = {
				type = "string",
				description = "Optional template name (e.g. 'rfc', 'meeting', 'bug', 'til', 'daily', or a custom template from notes_dir/templates/*.md). Ignored when parent is given.",
			},
			parent = {
				type = "string",
				description = "Parent task title; switches to the task-detail note convention and writes parent/source_note frontmatter",
			},
			source_note = {
				type = "string",
				description = "Source note reference (relative path); defaults to board_path when that is given",
			},
			date = { type = "string", description = "Frontmatter/date-stamped filename date; defaults to today" },
			board_path = {
				type = "string",
				description = "Optional board note to insert the new task's checklist line into",
			},
			heading = { type = "string", description = "Board heading/day to insert the line under, e.g. 'Tuesday'" },
			board_text = { type = "string", description = "Optional plain text before the link on the board line" },
			board_status = { type = "string", description = "Board checkbox status: 'todo' (default), 'doing', 'waiting', or 'done'" },
			parent_match = { type = "string", description = "Substring identifying the board's parent task line; defaults to parent" },
			parent_lnum = { type = "number", description = "1-based line number of the board's parent task line" },
			board_parent_match = { type = "string", description = "Explicit board parent substring (overrides parent_match)" },
			board_parent_lnum = { type = "number", description = "Explicit board parent line number (overrides parent_lnum)" },
			board_parent_link = { type = "string", description = "Wiki-link carried by the board's parent line" },
		},
		required = { "title" },
	},
	handler = handler,
}
