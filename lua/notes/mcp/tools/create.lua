-- lua/notes/mcp/tools/create.lua
--- MCP tool: notes_create — create a new note with frontmatter from an
--- optional named template; resolves filename collisions automatically.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local config = shared.config
local notes_dir = shared.notes_dir

local function handler(args)
	local title = args.title
	if not title or title == "" then
		return encode_checked(encode_json({ error = "title is required" }))
	end

	-- Sanitize the title for filename
	local sanitized = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
	sanitized = sanitized:gsub("-+", "-"):gsub("^-+", ""):gsub("-+$", "")

	local date = os.date(config.date_format or "%Y-%m-%d")
	local tags = args.tags or {}
	local tags_str = "[]"
	if type(tags) == "table" and #tags > 0 then
		local quoted = {}
		for _, t in ipairs(tags) do
			table.insert(quoted, '"' .. t:gsub('"', '\\"') .. '"')
		end
		tags_str = "[" .. table.concat(quoted, ", ") .. "]"
	end

	-- Build the note content (optional named template, else default)
	local DEFAULT_TEMPLATE = [[---
title: "%TITLE%"
date: "%DATE%"
tags: %TAGS%
summary: ""
---

# %TITLE%

%BODY%
]]

	local template = config.template or DEFAULT_TEMPLATE
	local template_dir

	if args.template and args.template ~= "" then
		local name = args.template
		local cfg_templates = config.templates or {}
		local resolved

		if name == "default" then
			resolved = config.template
		elseif cfg_templates[name] ~= nil then
			local t = cfg_templates[name]
			if type(t) == "string" then
				resolved = t
			elseif type(t) == "table" then
				local cfg_mod = require("notes.config")
				local builtin = cfg_mod._builtin_templates and cfg_mod._builtin_templates[name]
				resolved = t.content or builtin
				if t.directory then
					template_dir = notes_dir .. "/" .. t.directory:gsub("^/*", ""):gsub("/*$", "")
				end
			end
		elseif name == "daily" and not cfg_templates.daily then
			local dt = config.daily_template
			if type(dt) == "table" then
				resolved = dt.content or require("notes.config")._builtin_daily_template
			else
				resolved = dt
			end
		else
			-- File template: notes_dir/templates/<name>.md
			local file_path = notes_dir .. "/templates/" .. name .. ".md"
			if vim.fn.filereadable(file_path) == 1 then
				local f = io.open(file_path, "r")
				if f then
					resolved = f:read("*all")
					f:close()
				end
			end
		end

		if resolved == nil or resolved == "" then
			local names = { "default" }
			for k, _ in pairs(cfg_templates) do
				if type(k) == "string" then
					table.insert(names, k)
				end
			end
			table.sort(names)
			return encode_checked(encode_json({
				error = "unknown template: " .. name .. ". Available templates: " .. table.concat(names, ", "),
			}))
		end
		template = resolved
	end

	local content = (args.content or ""):gsub("^%s*$", "")
	local body =
		template:gsub("%%TITLE%%", title):gsub("%%DATE%%", date):gsub("%%TAGS%%", tags_str):gsub("%%BODY%%", content)

	-- Determine directory (explicit arg wins over the template's default directory)
	local target_dir = notes_dir
	if args.directory then
		target_dir = notes_dir .. "/" .. args.directory:gsub("^/*", ""):gsub("/*$", "")
	elseif template_dir then
		target_dir = template_dir
	end

	if vim.fn.isdirectory(target_dir) == 0 then
		vim.fn.mkdir(target_dir, "p")
	end

	-- Generate unique filename
	local filename = sanitized .. ".md"
	local filepath = target_dir .. "/" .. filename

	-- Handle name collision
	if vim.fn.filereadable(filepath) == 1 then
		local counter = 1
		while vim.fn.filereadable(filepath) == 1 do
			filename = string.format("%s_%d.md", sanitized, counter)
			filepath = target_dir .. "/" .. filename
			counter = counter + 1
		end
	end

	local f = io.open(filepath, "w")
	if not f then
		return encode_checked(encode_json({ error = "failed to create note at: " .. filepath }))
	end

	f:write(body)
	f:close()

	return encode_checked(encode_json({
		path = filepath,
		title = title,
		filename = filename,
		date = date,
	}))
end

return {
	name = "notes_create",
	description = "Create a new note with frontmatter from an optional named template. Returns the file path and title of the created note.",
	inputSchema = {
		type = "object",
		properties = {
			title = { type = "string", description = "Note title (used for filename and frontmatter)" },
			content = { type = "string", description = "Optional body content (markdown)" },
			tags = { type = "array", items = { type = "string" }, description = "Optional list of tags" },
			directory = {
				type = "string",
				description = "Optional subdirectory under notes (e.g. 'work/meetings')",
			},
			template = {
				type = "string",
				description = "Optional template name (e.g. 'default', 'rfc', 'meeting', 'bug', 'til', 'release', 'documentation', 'job_application', 'daily', or a custom template from notes_dir/templates/*.md). Falls back to the default template.",
			},
		},
		required = { "title" },
	},
	handler = handler,
}
