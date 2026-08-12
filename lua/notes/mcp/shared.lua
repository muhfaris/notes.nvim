-- lua/notes/mcp/shared.lua
--- Shared helpers and state for the notes.nvim MCP server:
--- config, notes_dir, JSON encode/decode, path resolution, and note parsing.
--- Tool modules under `lua/notes/mcp/tools/` require this module.

local M = {}

-- ── Config ──────────────────────────────────────────────────────────────

--- Try loading the user's notes.nvim config; fall back to env vars + defaults.
local config
local ok, cfg_mod = pcall(require, "notes.config")
if ok then
	config = cfg_mod.get_config() or cfg_mod.config
end

if not config then
	config = {
		notes_dir = vim.env.NOTES_DIR or vim.fn.expand("~/.notes"),
		date_format = "%Y-%m-%d",
		length_title = 60,
		template = [[---
title: "%TITLE%"
date: "%DATE%"
tags: []
summary: ""
---

# %TITLE%

%BODY%
]],
	}
end

M.config = config

--- Canonical absolute path used by every tool that resolves note paths.
M.notes_dir = vim.fn.fnamemodify(vim.fn.expand(config.notes_dir), ":p"):gsub("/+$", "")

-- ── JSON helpers ───────────────────────────────────────────────────────

M.encode_json = function(t)
	local ok, result = pcall(vim.json.encode, t)
	if ok then
		return result
	end
	return nil
end

-- Return an encoded payload, or a safe fallback error string if encoding fails.
local ENCODE_FAILED = '{"error":"internal error: failed to encode response"}'

M.encode_checked = function(result)
	if result == nil then
		return ENCODE_FAILED
	end
	return result
end

M.decode_json = function(s)
	local ok, result = pcall(vim.json.decode, s)
	if ok then
		return result
	end
	return nil
end

-- ── Path resolution ─────────────────────────────────────────────────────

--- Resolve a tool-supplied path: absolute paths used as-is, relative
--- paths resolved against the notes directory.
M.resolve_path = function(path)
	if path:sub(1, 1) == "/" then
		return path
	end
	return M.notes_dir .. "/" .. path
end

-- ── Note parsing ───────────────────────────────────────────────────────

--- Parse a single note file into metadata + body (+ fallback date from mtime).
M.parse_note = function(note_path)
	local parser
	local ok_parse, parser_mod = pcall(require, "notes.parser")
	if ok_parse then
		parser = parser_mod
	end

	local metadata, body
	if parser then
		metadata, body = parser.read_file(note_path)
	else
		-- Fallback: read file and do a basic frontmatter parse
		local f = io.open(note_path, "r")
		if f then
			local content = f:read("*all")
			f:close()
			metadata = { title = vim.fn.fnamemodify(note_path, ":t:r"), date = "", tags = {}, summary = "" }
			body = content
		end
	end

	if not metadata then
		return nil
	end

	local date = metadata.date or ""
	if date == "" then
		local mtime = vim.fn.getftime(note_path)
		date = os.date("%Y-%m-%d %H:%M:%S", mtime)
	end

	return {
		path = note_path,
		title = metadata.title or vim.fn.fnamemodify(note_path, ":t:r"),
		date = date,
		tags = metadata.tags or {},
		summary = metadata.summary or "",
		body = body,
	}
end

-- ── Note scanning ──────────────────────────────────────────────────────

--- Scan all markdown notes under notes_dir, skipping templates/.
M.scan_notes = function()
	local files = vim.fn.globpath(M.notes_dir, "**/*.md", false, true)
	local results = {}
	for _, path in ipairs(files) do
		local rel = path:sub(#M.notes_dir + 2)
		if rel:sub(1, 10) ~= "templates/" then
			local note = M.parse_note(path)
			if note then
				table.insert(results, note)
			end
		end
	end
	return results
end

-- ── Metadata normalization ─────────────────────────────────────────────

-- Core fields that are always present in a predictable shape.
local META_STANDARD = {
	title = true,
	date = true,
	tags = true,
	summary = true,
}

M.normalize_metadata = function(metadata)
	local out = {
		title = metadata.title or "",
		date = metadata.date or "",
		tags = metadata.tags or {},
		summary = metadata.summary or "",
	}
	for key, value in pairs(metadata) do
		if not META_STANDARD[key] and type(value) ~= "table" and value ~= nil and value ~= "" then
			out[key] = value
		end
	end
	return out
end

return M
