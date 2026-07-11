-- lua/notes/notion/resolver.lua
local M = {}

--- Resolve the target Notion Database ID and Properties mapping for a note.
--- @param filepath string Absolute path to the note file.
--- @param metadata table Parsed YAML frontmatter metadata table.
--- @return string|nil database_id The resolved Notion Database ID.
--- @return table|nil properties The resolved properties schema mapping.
function M.resolve_database(filepath, metadata)
	local config_mod = require("notes.config")
	local config = config_mod.get_config()
	local notion_opts = config.notion

	if not notion_opts or not notion_opts.enabled then
		return nil, nil
	end

	local default_db = notion_opts.default_database or {}
	local default_props = default_db.properties or {
		title = "Name",
		tags = "Tags",
		date = "Date",
		summary = "Summary",
	}

	-- 1. Check if the database ID is directly overridden in the note's frontmatter
	if metadata.notion_database_id and metadata.notion_database_id ~= "" then
		local db_id = metadata.notion_database_id

		-- Check if we have custom properties defined for this specific DB ID in mappings
		if default_db.database_id == db_id then
			return db_id, default_db.properties or default_props
		end

		for _, db_config in pairs(notion_opts.directory_mappings) do
			if type(db_config) == "table" and db_config.database_id == db_id then
				return db_id, db_config.properties or default_props
			end
		end

		for _, db_config in pairs(notion_opts.tag_mappings) do
			if type(db_config) == "table" and db_config.database_id == db_id then
				return db_id, db_config.properties or default_props
			end
		end

		return db_id, default_props
	end

	-- 2. Check directory mappings
	if notion_opts.directory_mappings then
		for pattern, db_config in pairs(notion_opts.directory_mappings) do
			if filepath:find(pattern, 1, true) then
				if type(db_config) == "table" then
					return db_config.database_id, db_config.properties or default_props
				else
					return db_config, default_props
				end
			end
		end
	end

	-- 3. Check tag mappings
	if metadata.tags and type(metadata.tags) == "table" and notion_opts.tag_mappings then
		for _, tag in ipairs(metadata.tags) do
			local db_config = notion_opts.tag_mappings[tag]
			if db_config then
				if type(db_config) == "table" then
					return db_config.database_id, db_config.properties or default_props
				else
					return db_config, default_props
				end
			end
		end
	end

	-- 4. Fallback to default database config
	if default_db.database_id then
		return default_db.database_id, default_db.properties or default_props
	end

	return nil, nil
end

--- Get the page ID of the note from frontmatter metadata.
--- @param metadata table Parsed YAML frontmatter metadata.
--- @return string|nil page_id The page ID if mapped, nil otherwise.
function M.get_page_id(metadata)
	if metadata.notion_page_id and metadata.notion_page_id ~= "" then
		return metadata.notion_page_id
	end
	return nil
end

--- Write a Notion Page ID back to the note file's YAML frontmatter.
--- @param filepath string Absolute path to the note file.
--- @param page_id string The Notion Page ID.
--- @return boolean success
--- @return string|nil error_msg
function M.write_page_id(filepath, page_id)
	local parser = require("notes.parser")
	local metadata, body = parser.read_file(filepath)
	if not metadata then
		return false, "Failed to read file or frontmatter"
	end

	metadata.notion_page_id = page_id

	local formatted = parser.format_frontmatter(metadata) .. "\n" .. body
	local f = io.open(filepath, "w")
	if not f then
		return false, "Failed to write file"
	end

	f:write(formatted)
	f:close()
	return true
end

return M
