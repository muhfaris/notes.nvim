-- lua/notes/toc.lua
local M = {}
local config = require("notes.config").get_config()

-- Generate a clean GitHub-style anchor slug from a heading string
local function generate_slug(text)
	-- Remove markdown links from heading text if any (e.g. [some text](link) -> some text)
	local clean_text = text:gsub("%b[]%b()", function(m)
		return m:match("%[([^%]]+)%]") or m
	end)
	-- Remove other markdown styling like bold, italic, code backticks
	clean_text = clean_text:gsub("[`*_~]", "")
	-- Lowercase
	local slug = clean_text:lower()
	-- Replace spaces and tabs with hyphens
	slug = slug:gsub("[%s\t]+", "-")
	-- Remove non-alphanumeric, non-hyphen, non-underscore characters
	slug = slug:gsub("[^%w-_]", "")
	-- Clean up multiple hyphens
	slug = slug:gsub("-+", "-")
	-- Trim hyphens from start and end
	slug = slug:gsub("^-+", ""):gsub("-+$", "")
	return slug
end

-- Scan the buffer and return a list of headings, skipping code blocks
M.parse_headings = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return {}
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local headings = {}
	local in_code_block = false
	local slug_counts = {}

	for i, line in ipairs(lines) do
		-- Detect code block fences
		if line:match("^%s*```") then
			in_code_block = not in_code_block
		end

		if not in_code_block then
			local hash_prefix, heading_text = line:match("^(#+)%s+(.-)%s*$")
			if hash_prefix and heading_text ~= "" then
				local level = #hash_prefix
				local base_slug = generate_slug(heading_text)
				local slug = base_slug
				if slug_counts[base_slug] then
					slug_counts[base_slug] = slug_counts[base_slug] + 1
					slug = base_slug .. "-" .. slug_counts[base_slug]
				else
					slug_counts[base_slug] = 0
				end

				table.insert(headings, {
					level = level,
					text = heading_text,
					lnum = i,
					slug = slug,
				})
			end
		end
	end
	return headings
end

-- Generate table of contents lines from list of headings
M.generate_toc_lines = function(headings, max_level)
	max_level = max_level or config.toc_max_level or 4
	local toc_lines = {}
	for _, heading in ipairs(headings) do
		if heading.level <= max_level then
			-- Indent based on level (level 1 has 0 indent, level 2 has 2 spaces, etc.)
			local indent = string.rep(" ", (heading.level - 1) * 2)
			table.insert(toc_lines, string.format("%s* [%s](#%s)", indent, heading.text, heading.slug))
		end
	end
	return toc_lines
end

-- In-place update of TOC block in the buffer if markers are found
M.update_toc = function(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local start_idx = nil
	local end_idx = nil

	-- Search for markers
	for i, line in ipairs(lines) do
		if line:match("^%s*<!%-%-%s*TOC%s*%-%->%s*$") or line:match("^%s*<!%-%-%s*TOC_START%s*%-%->%s*$") then
			start_idx = i
		elseif line:match("^%s*<!%-%-%s*/TOC%s*%-%->%s*$") or line:match("^%s*<!%-%-%s*TOC_END%s*%-%->%s*$") then
			end_idx = i
			if start_idx then
				break
			end
		end
	end

	if not start_idx or not end_idx or start_idx >= end_idx then
		return false
	end

	local headings = M.parse_headings(bufnr)
	
	-- Exclude any headings that are inside the TOC block itself
	local filtered_headings = {}
	for _, heading in ipairs(headings) do
		if heading.lnum < start_idx or heading.lnum > end_idx then
			table.insert(filtered_headings, heading)
		end
	end

	local toc_lines = M.generate_toc_lines(filtered_headings)

	-- Replace lines between the start marker (line start_idx) and end marker (line end_idx)
	vim.api.nvim_buf_set_lines(bufnr, start_idx, end_idx - 1, false, toc_lines)
	return true
end

return M
