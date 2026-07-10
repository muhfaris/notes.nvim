-- lua/notes/parser.lua
local M = {}

local function parse_tags(val)
	if not val or val == "" then
		return {}
	end
	-- Check if formatted as [tag1, tag2]
	local inside = val:match("^%[(.*)%]$")
	if inside then
		val = inside
	end
	local tags = {}
	for tag in val:gmatch("[^,]+") do
		tag = vim.trim(tag):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
		if tag ~= "" then
			table.insert(tags, tag)
		end
	end
	return tags
end

-- Parse frontmatter from file content
M.parse = function(content, filename)
	local lines = vim.split(content, "\n")
	if #lines == 0 or lines[1] ~= "---" then
		return M.parse_fallback(content, filename)
	end

	local metadata = {
		title = "",
		date = "",
		tags = {},
		summary = "",
	}
	local body_start_idx = nil
	local i = 2
	local current_key = nil

	while i <= #lines do
		local line = lines[i]
		if line == "---" then
			body_start_idx = i + 1
			break
		end

		-- Match key: value
		local key, val = line:match("^([%w_]+)%s*:%s*(.*)$")
		if key then
			key = key:lower()
			val = vim.trim(val):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			if val == "" then
				current_key = key
				if key == "tags" or key == "keywords" then
					metadata.tags = {}
				else
					metadata[key] = ""
				end
			else
				current_key = nil
				if key == "tags" or key == "keywords" then
					metadata.tags = parse_tags(val)
				else
					metadata[key] = val
				end
			end
		elseif current_key and line:match("^%s*-%s+(.*)$") then
			local item = line:match("^%s*-%s+(.*)$")
			item = vim.trim(item):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			if current_key == "tags" or current_key == "keywords" then
				table.insert(metadata.tags, item)
			else
				metadata[current_key] = item
			end
		end
		i = i + 1
	end

	if not body_start_idx then
		return M.parse_fallback(content, filename)
	end

	local body_lines = {}
	for j = body_start_idx, #lines do
		table.insert(body_lines, lines[j])
	end

	-- Normalize keywords to tags
	if metadata.keywords and #metadata.tags == 0 then
		metadata.tags = metadata.keywords
	end

	return metadata, table.concat(body_lines, "\n")
end

-- Parse old format for backwards compatibility
M.parse_fallback = function(content, filename)
	local title = content:match("^# Title:%s*(.-)\n")
	local summary = content:match("## Summary\n(.-)\n##")
	local keywords_line = content:match("## Keywords:%s*(.-)\n")

	local metadata = {
		title = title or vim.fn.fnamemodify(filename, ":t:r"),
		summary = summary and vim.trim(summary) or "",
		tags = {},
		date = "",
	}

	if keywords_line then
		metadata.tags = parse_tags(keywords_line)
	end

	local date_line = content:match("## Date:%s*(.-)\n")
	if date_line then
		metadata.date = vim.trim(date_line)
	end

	return metadata, content
end

-- Read and parse a file by path
M.read_file = function(filepath)
	local file = io.open(filepath, "r")
	if not file then
		return nil
	end
	local content = file:read("*all")
	file:close()
	return M.parse(content, filepath)
end

-- Format frontmatter as a YAML string
M.format_frontmatter = function(metadata)
	local lines = { "---" }
	table.insert(lines, string.format('title: "%s"', (metadata.title or ""):gsub('"', '\\"')))
	table.insert(lines, string.format('date: "%s"', metadata.date or ""))

	local tags_str = "[]"
	if type(metadata.tags) == "table" and #metadata.tags > 0 then
		local quoted = {}
		for _, tag in ipairs(metadata.tags) do
			table.insert(quoted, string.format('"%s"', tag:gsub('"', '\\"')))
		end
		tags_str = "[" .. table.concat(quoted, ", ") .. "]"
	end
	table.insert(lines, string.format("tags: %s", tags_str))
	table.insert(lines, string.format('summary: "%s"', (metadata.summary or ""):gsub('"', '\\"')))
	table.insert(lines, "---")

	return table.concat(lines, "\n")
end

return M
