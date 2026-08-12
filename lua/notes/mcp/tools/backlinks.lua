-- lua/notes/mcp/tools/backlinks.lua
--- MCP tool: notes_backlinks — find notes that link to a target note.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local notes_dir = shared.notes_dir
local resolve_path = shared.resolve_path
local parse_note = shared.parse_note
local scan_notes = shared.scan_notes

local function link_candidates(note_path, note)
	local candidates = {}
	local function add(value)
		if value and value ~= "" then
			for _, existing in ipairs(candidates) do
				if existing == value then
					return
				end
			end
			table.insert(candidates, value)
		end
	end

	add(note.title)
	add(vim.fn.fnamemodify(note_path, ":t:r"))

	local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
	add(rel_path)
	add(rel_path:gsub("%.md$", ""))

	return candidates
end

local function handler(args)
	local path = args.path
	if not path or path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local target_path = vim.fn.resolve(resolve_path(path))
	if vim.fn.filereadable(target_path) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. path }))
	end

	local notes_abs = vim.fn.resolve(notes_dir)
	if target_path:sub(1, #notes_abs) ~= notes_abs then
		return encode_checked(encode_json({ error = "note is outside notes directory: " .. path }))
	end

	local target = parse_note(target_path)
	if not target then
		return encode_checked(encode_json({ error = "failed to parse target note: " .. path }))
	end

	local candidates = link_candidates(target_path, target)
	local links = {}
	for _, candidate in ipairs(candidates) do
		table.insert(links, "[[" .. candidate .. "]]")
	end

	local results = {}
	for _, note in ipairs(scan_notes()) do
		if vim.fn.resolve(note.path) ~= target_path then
			local matched_links = {}
			local content = note.body or ""
			for _, link in ipairs(links) do
				if content:find(link, 1, true) then
					table.insert(matched_links, link)
				end
			end

			if #matched_links > 0 then
				table.insert(results, {
					path = note.path,
					relative_path = note.path:sub(#notes_dir + 2),
					title = note.title,
					date = note.date,
					tags = note.tags,
					matched_links = matched_links,
				})
			end
		end
	end

	table.sort(results, function(a, b)
		return (a.date or "") > (b.date or "")
	end)

	return encode_checked(encode_json({
		target = {
			path = target_path,
			relative_path = target_path:sub(#notes_dir + 2),
			title = target.title,
		},
		backlinks = results,
		count = #results,
	}))
end

return {
	name = "notes_backlinks",
	description = "Find notes containing wiki-links to a target note.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Target note path, relative to notes_dir or absolute" },
		},
		required = { "path" },
	},
	handler = handler,
}
