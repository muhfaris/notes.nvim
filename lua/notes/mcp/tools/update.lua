-- lua/notes/mcp/tools/update.lua
--- MCP tool: notes_update — update an existing note's content and/or
--- frontmatter fields (title, tags, summary, date, custom fields). Only the
--- fields provided are changed; omitted fields are preserved.
---
--- Pass `expected_hash` (from notes_read) to make the write conditional: if
--- somebody else changed the file in the meantime, the update is refused
--- instead of overwriting their edit.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	-- Which fields does the caller want to change?
	local changed = {}
	local updatable = { "title", "tags", "summary", "date", "metadata", "content" }
	for _, field in ipairs(updatable) do
		if args[field] ~= nil then
			table.insert(changed, field)
		end
	end
	if #changed == 0 then
		return encode_checked(encode_json({
			error = "nothing to update: provide at least one of content, title, tags, summary, date, metadata",
		}))
	end

	-- Read once: the hash we check must describe exactly the content we rewrite.
	local content = shared.read_content(abs_path)
	if not content then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end
	local current_hash = shared.hash_content(content)
	if not shared.hash_matches(args.expected_hash, current_hash) then
		return encode_checked(encode_json(shared.stale_note_error(abs_path, args.expected_hash, current_hash)))
	end

	-- Parse the content we just read (metadata + body)
	local metadata, body
	local ok_parse, parser_mod = pcall(require, "notes.parser")
	if ok_parse then
		metadata, body = parser_mod.parse(content, abs_path)
	end

	if not metadata then
		-- Fallback: minimal parse so we never clobber a file blindly
		body = content
		metadata = {
			title = vim.fn.fnamemodify(abs_path, ":t:r"),
			date = "",
			tags = {},
			summary = "",
		}
	end

	-- Apply field updates
	if args.title ~= nil then
		metadata.title = tostring(args.title)
	end
	if args.tags ~= nil then
		local tags = {}
		if type(args.tags) == "table" then
			for _, t in ipairs(args.tags) do
				table.insert(tags, tostring(t))
			end
		end
		metadata.tags = tags
	end
	if args.summary ~= nil then
		metadata.summary = tostring(args.summary)
	end
	if args.date ~= nil then
		metadata.date = tostring(args.date)
	end
	if args.metadata ~= nil and type(args.metadata) == "table" then
		if #args.metadata > 0 then
			for _, entry in ipairs(args.metadata) do
				if type(entry) == "table" and entry.key and type(entry.value) ~= "table" then
					metadata[tostring(entry.key)] = tostring(entry.value)
				end
			end
		else
			-- Backward compatibility for non-strict MCP clients using the old map.
			for key, value in pairs(args.metadata) do
				if type(value) ~= "table" then
					metadata[key] = tostring(value)
				end
			end
		end
	end

	-- Build new file content
	local new_body = body or ""
	if args.content ~= nil then
		new_body = args.content
	end

	local new_content
	if ok_parse then
		new_content = parser_mod.format_frontmatter(metadata) .. "\n" .. new_body
	else
		new_content = new_body
	end

	local hash = shared.write_content(abs_path, new_content)
	if not hash then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end

	return encode_checked(encode_json({
		success = true,
		path = abs_path,
		relative_path = shared.relative_path(abs_path),
		title = metadata.title,
		tags = metadata.tags,
		summary = metadata.summary,
		date = metadata.date,
		changed = changed,
		hash = hash,
	}))
end

return {
	name = "notes_update",
	description = "Update an existing note's content and/or frontmatter fields (title, tags, summary, date, custom fields). Only the fields provided are changed; omitted fields are preserved. `path` may be a full path, filename, or title. Pass `expected_hash` (from notes_read) to refuse the write if the note changed in the meantime; on conflict the result has code `stale_note` and the current hash.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
			content = {
				type = "string",
				description = "New body content (markdown). Replaces the note body; frontmatter is preserved.",
			},
			title = { type = "string", description = "New title in frontmatter (filename is unchanged)" },
			tags = { type = "array", items = { type = "string" }, description = "Replaces all tags" },
			summary = { type = "string", description = "New summary" },
			date = { type = "string", description = "New date" },
			expected_hash = {
				type = "string",
				description = "Hash returned by notes_read; rejects the update with code 'stale_note' if the file changed since then",
			},
			metadata = {
				type = "array",
				description = "Custom frontmatter fields as key/value entries (scalar values only)",
				items = {
					type = "object",
					properties = {
						key = { type = "string", description = "Frontmatter field name" },
						value = {
							type = { "string", "number", "boolean" },
							description = "Frontmatter scalar value",
						},
					},
					required = { "key", "value" },
				},
			},
		},
		required = { "path" },
	},
	handler = handler,
}
