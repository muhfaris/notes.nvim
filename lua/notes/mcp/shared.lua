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
--- `content` may be supplied when the caller already read the file, so the
--- returned fields and the caller's hash describe the same bytes.
M.parse_note = function(note_path, content)
	local parser
	local ok_parse, parser_mod = pcall(require, "notes.parser")
	if ok_parse then
		parser = parser_mod
	end

	local metadata, body
	if parser then
		if content ~= nil then
			metadata, body = parser.parse(content, note_path)
		else
			metadata, body = parser.read_file(note_path)
		end
	else
		-- Fallback: read file and do a basic frontmatter parse
		if content == nil then
			local f = io.open(note_path, "r")
			if f then
				content = f:read("*all")
				f:close()
			end
		end
		if content ~= nil then
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

-- ── Note lookup: exact path, then name/title, then suggestions ─────────
-- A caller often knows a note by its filename or title, not its full path
-- (notes_read("w2-oct-2026.md")). Resolution therefore falls back to a
-- basename/title search across the vault and, when nothing matches, returns
-- near misses so the caller can retry without a filesystem hunt.

M.clean_link = function(link)
	local body = tostring(link or ""):gsub("\r", "")
	body = body:gsub("^%s*%[%[", ""):gsub("%]%]%s*$", "")
	body = body:gsub("\\", "/")
	body = body:gsub("|.*$", "")
	body = body:gsub("#.*$", "")
	return vim.trim(body)
end

M.normalize_slug = function(value)
	value = tostring(value or ""):lower():gsub("%%", " ")
	value = value:gsub("[^%w]+", "-")
	return value:gsub("^-+", ""):gsub("-+$", "")
end

M.note_paths = function()
	local paths = {}
	for _, path in ipairs(vim.fn.globpath(M.notes_dir, "**/*.md", false, true)) do
		local rel = path:sub(#M.notes_dir + 2):gsub("\\", "/")
		if rel:sub(1, 10) ~= "templates/" then
			table.insert(paths, path)
		end
	end
	return paths
end

--- Every note's searchable identity: relative path, filename stem, and title.
M.note_index = function()
	local index = {}
	local parser = require("notes.parser")
	for _, path in ipairs(M.note_paths()) do
		local metadata = parser.read_file(path) or {}
		local rel = path:sub(#M.notes_dir + 2):gsub("\\", "/")
		local basename = vim.fn.fnamemodify(path, ":t")
		local stem = basename:gsub("%.md$", "")
		local title = metadata.title
		if not title or title == "" then
			title = stem
		end
		table.insert(index, {
			path = path,
			relative_path = rel,
			basename = basename,
			stem = stem,
			title = title,
			date = metadata.date or "",
			stem_slug = M.normalize_slug(stem),
			title_slug = M.normalize_slug(title),
			relative_slug = M.normalize_slug((rel:gsub("%.md$", ""))),
		})
	end
	return index
end

local function public_entry(entry)
	return {
		path = entry.path,
		relative_path = entry.relative_path,
		title = entry.title,
		date = entry.date,
	}
end

local function levenshtein(a, b)
	local la, lb = #a, #b
	if la == 0 then
		return lb
	end
	if lb == 0 then
		return la
	end
	local prev = {}
	for j = 0, lb do
		prev[j] = j
	end
	for i = 1, la do
		local cur = { [0] = i }
		for j = 1, lb do
			local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev = cur
	end
	return prev[lb]
end

--- Closest notes to `query`, best first. Uses token overlap plus an edit
--- distance over the normalized filename/title/path, so a misspelled or
--- partial path still gets a usable "did you mean" list.
M.suggest_notes = function(query, limit)
	local q = vim.trim(tostring(query or ""))
	if q == "" then
		return {}
	end
	local q_lower = q:lower()
	local q_slug = M.normalize_slug((q:gsub("%.md$", "")))
	local scored = {}

	for _, entry in ipairs(M.note_index()) do
		local haystack = (entry.title .. " " .. entry.stem .. " " .. entry.relative_path):lower()
		local overlap = 0
		for token in q_lower:gmatch("[%w]+") do
			if #token >= 2 and haystack:find(token, 1, true) then
				overlap = overlap + 1
			end
		end

		local distance = math.min(
			levenshtein(q_slug, entry.stem_slug),
			levenshtein(q_slug, entry.title_slug),
			levenshtein(q_slug, entry.relative_slug)
		)
		local score = distance - overlap * 2
		local direct = q_slug ~= ""
			and (
				entry.stem_slug:find(q_slug, 1, true) ~= nil
				or entry.title_slug:find(q_slug, 1, true) ~= nil
				or q_slug:find(entry.stem_slug, 1, true) ~= nil
			)
		if direct then
			score = score - 5
		end
		table.insert(scored, { entry = entry, score = score, distance = distance })
	end

	table.sort(scored, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.entry.relative_path < b.entry.relative_path
	end)

	local out = {}
	local threshold = math.max(6, math.floor(#q_slug / 2))
	for _, candidate in ipairs(scored) do
		if #out >= (limit or 5) then
			break
		end
		if candidate.score <= threshold or candidate.distance <= 3 then
			table.insert(out, public_entry(candidate.entry))
		end
	end
	return out
end

local function match_note_index(query, index)
	local q_lower = query:lower()
	local q_stem = (query:gsub("%.md$", "")):lower()
	local q_slug = M.normalize_slug(q_stem)
	local q_last = query:match("([^/]+)$")
	local q_last_slug = q_last and M.normalize_slug((q_last:gsub("%.md$", ""))) or ""
	local tiers = {
		function(entry)
			return entry.relative_path:lower() == q_lower
				or (entry.relative_path:gsub("%.md$", "")):lower() == q_stem
		end,
		function(entry)
			return entry.basename:lower() == q_lower or entry.stem:lower() == q_stem
		end,
		function(entry)
			return entry.title:lower() == q_lower
		end,
		function(entry)
			return q_slug ~= "" and (entry.stem_slug == q_slug or entry.title_slug == q_slug)
		end,
		function(entry)
			return q_slug ~= "" and entry.relative_slug == q_slug
		end,
		function(entry)
			-- `Parent/Child` where the detail note's own title is `Child`.
			return q_slug ~= "" and #entry.title_slug >= 3 and q_slug:sub(-(#entry.title_slug + 1)) == "-" .. entry.title_slug
		end,
		function(entry)
			return q_last_slug ~= ""
				and q_slug ~= q_last_slug
				and (entry.stem_slug == q_last_slug or entry.title_slug == q_last_slug)
		end,
	}

	for _, tier in ipairs(tiers) do
		local hits, seen = {}, {}
		for _, entry in ipairs(index) do
			if tier(entry) and not seen[entry.path] then
				seen[entry.path] = true
				table.insert(hits, entry)
			end
		end
		if #hits > 0 then
			return hits
		end
	end
	return {}
end

--- Resolve a caller-supplied note reference.
--- @return string|nil abs_path, table info
---   info.match is "path" or "name" on success. On failure info is either
---   { ambiguous = true, candidates = {...} } or { suggestions = {...} }.
M.resolve_note_path = function(path, opts)
	opts = opts or {}
	if type(path) ~= "string" or vim.trim(path) == "" then
		return nil, { suggestions = {} }
	end

	local cleaned = M.clean_link(path):gsub("\\", "/")
	local tried = {}

	local function try(abs)
		if not abs or tried[abs] then
			return nil
		end
		tried[abs] = true
		local trimmed = abs:gsub("/+$", "")
		if vim.fn.filereadable(trimmed) == 1 then
			return trimmed
		end
		if vim.fn.filereadable(trimmed .. ".md") == 1 then
			return trimmed .. ".md"
		end
		return nil
	end

	local direct
	if cleaned:sub(1, 1) == "/" or cleaned:sub(1, 2) == "~/" then
		local abs = vim.fn.fnamemodify(vim.fn.expand(cleaned), ":p"):gsub("/+$", "")
		direct = try(abs)
	else
		local rel = cleaned:gsub("^%./", "")
		direct = try(M.notes_dir .. "/" .. rel)
		if not direct and opts.from_path and opts.from_path ~= "" then
			direct = try(vim.fn.fnamemodify(opts.from_path, ":h") .. "/" .. rel)
		end
	end

	if direct then
		return direct, {
			match = "path",
			relative_path = M.relative_path(direct),
		}
	end

	local hits = match_note_index(cleaned, M.note_index())
	if #hits == 1 then
		return hits[1].path, {
			match = "name",
			relative_path = hits[1].relative_path,
			title = hits[1].title,
		}
	end
	if #hits > 1 then
		local candidates = {}
		for _, entry in ipairs(hits) do
			table.insert(candidates, public_entry(entry))
		end
		return nil, { ambiguous = true, candidates = candidates }
	end

	return nil, { suggestions = M.suggest_notes(cleaned) }
end

M.note_lookup_error = function(input, info)
	info = info or {}
	if info.ambiguous then
		local names = {}
		for _, candidate in ipairs(info.candidates or {}) do
			table.insert(names, candidate.relative_path)
		end
		local message = "ambiguous note path: " .. tostring(input)
		if #names > 0 then
			message = message .. " (matches: " .. table.concat(names, ", ") .. ")"
		end
		return { error = message, candidates = info.candidates }
	end

	local out = { error = "note not found: " .. tostring(input) }
	if info.suggestions and #info.suggestions > 0 then
		local names = {}
		for _, suggestion in ipairs(info.suggestions) do
			table.insert(names, suggestion.relative_path)
		end
		out.error = out.error .. " (did you mean: " .. table.concat(names, ", ") .. "?)"
		out.suggestions = info.suggestions
	end
	return out
end

M.resolve_note_or_error = function(path, opts)
	local abs_path, info = M.resolve_note_path(path, opts)
	if abs_path then
		return abs_path, nil
	end
	return nil, M.note_lookup_error(path, info)
end

--- Resolve a wiki-link body (with or without `[[ ]]`, alias, anchor) to a
--- note path. Direct paths win; then a `Parent/Child` detail-note title match.
M.resolve_link = function(link, opts)
	opts = opts or {}
	local body = M.clean_link(link)
	if body == "" then
		return nil, { suggestions = {} }
	end

	local abs_path, info = M.resolve_note_path(body, { from_path = opts.from_path })
	if abs_path then
		info = info or {}
		info.link = body
		return abs_path, info
	end
	-- An ambiguous name stays ambiguous: falling through to the detail-note
	-- fallback would silently choose one of the candidates.
	if info and info.ambiguous then
		return nil, info
	end

	local detail = require("notes.shared.tasks").resolve_detail_link(body, M.notes_dir)
	if detail then
		return detail, {
			match = "detail_title",
			link = body,
			relative_path = M.relative_path(detail),
		}
	end

	return nil, info or { suggestions = M.suggest_notes(body) }
end

-- ── Versioned reads/writes ──────────────────────────────────────────────
-- notes_read returns a content hash; writers that accept `expected_hash`
-- refuse to write when the file changed in between, so an agent cannot
-- silently overwrite a concurrent edit.

M.read_content = function(abs_path)
	local f = io.open(abs_path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

M.hash_content = function(content)
	if content == nil then
		return nil
	end
	return "sha256:" .. vim.fn.sha256(content)
end

M.file_hash = function(abs_path)
	return M.hash_content(M.read_content(abs_path))
end

M.write_content = function(abs_path, content)
	local f, err = io.open(abs_path, "w")
	if not f then
		return nil, err
	end
	f:write(content)
	f:close()
	return M.hash_content(content)
end

M.hash_matches = function(expected, current)
	if not expected or expected == "" then
		return true
	end
	return current == expected or current == "sha256:" .. expected
end

M.check_expected_hash = function(abs_path, expected)
	if not expected or expected == "" then
		return true
	end
	local current = M.file_hash(abs_path)
	if M.hash_matches(expected, current) then
		return true
	end
	return false, current
end

M.stale_note_error = function(abs_path, expected, current)
	return {
		error = "stale note: content changed since it was read; re-read it and retry",
		code = "stale_note",
		path = abs_path,
		expected_hash = expected,
		current_hash = current,
	}
end

-- ── Heading / task-line location ────────────────────────────────────────

--- Find a heading by text. Exact matches beat substring matches. Returns
--- (lnum) when unique; (nil, entries) when missing or ambiguous.
M.find_heading = function(lines, name)
	local needle = vim.trim(tostring(name or "")):gsub("^#+%s*", "")
	if needle == "" then
		return nil, {}
	end
	local exact, partial, all = {}, {}, {}
	for i, line in ipairs(lines) do
		local text = line:match("^#+%s+(.*)$")
		if text then
			text = vim.trim((text:gsub("%s*%[%[[^%]]*%]%]%s*$", "")))
			table.insert(all, { lnum = i, heading = text })
			if text:lower() == needle:lower() then
				table.insert(exact, { lnum = i, heading = text })
			elseif text:lower():find(needle:lower(), 1, true) then
				table.insert(partial, { lnum = i, heading = text })
			end
		end
	end
	if #exact == 1 then
		return exact[1].lnum
	end
	if #exact > 1 then
		return nil, exact
	end
	if #partial == 1 then
		return partial[1].lnum
	end
	if #partial > 1 then
		return nil, partial
	end
	return nil, all
end

M.section_end = function(lines, heading_lnum)
	local hashes = lines[heading_lnum] and lines[heading_lnum]:match("^(#+)")
	local level = hashes and #hashes or 1
	for i = heading_lnum + 1, #lines do
		local next_hashes = lines[i]:match("^(#+)%s")
		if next_hashes and #next_hashes <= level then
			return i - 1
		end
	end
	return #lines
end

M.line_has_link = function(line, link)
	local target = M.clean_link(link):gsub("%.md$", ""):lower()
	if target == "" then
		return false
	end
	for body in line:gmatch("%[%[([^%]]+)%]%]") do
		local candidate = M.clean_link(body):gsub("%.md$", ""):lower()
		if candidate == target or candidate:sub(-(#target + 1)) == "/" .. target then
			return true
		end
	end
	return false
end

--- Locate checklist lines in `lines`.
--- opts: lnum, match (plain substring), link, heading (restrict to section).
M.find_task_lines = function(lines, opts)
	opts = opts or {}
	local tasks_shared = require("notes.shared.tasks")
	local start_i, end_i = 1, #lines

	if opts.heading and opts.heading ~= "" then
		local heading_lnum, headings = M.find_heading(lines, opts.heading)
		if not heading_lnum then
			return nil, {
				error = "heading not found: " .. tostring(opts.heading),
				headings = headings,
			}
		end
		start_i = heading_lnum + 1
		end_i = M.section_end(lines, heading_lnum)
	end

	if opts.lnum then
		local line = lines[opts.lnum]
		if opts.lnum >= start_i and opts.lnum <= end_i and line and tasks_shared.is_task_line(line) then
			return { { lnum = opts.lnum, line = line } }
		end
		return {}
	end

	local link = opts.link and M.clean_link(opts.link) or nil
	local match = opts.match and tostring(opts.match) or nil
	local hits, exact_hits = {}, {}
	for i = start_i, end_i do
		local line = lines[i]
		if tasks_shared.is_task_line(line) then
			local ok = true
			if match and match ~= "" then
				ok = line:find(match, 1, true) ~= nil
			end
			if ok and link and link ~= "" then
				ok = M.line_has_link(line, link)
			end
			if ok then
				local entry = { lnum = i, line = line }
				table.insert(hits, entry)
				if match and match ~= "" then
					-- `Bug Finding` is a substring of `[[ Bug Finding/Child ]]`
					-- too; an exact task label must win over those children.
					local parsed = tasks_shared.parse_task_line(line)
					local rest = vim.trim(parsed and parsed.rest or "")
					local display = tasks_shared.display_task_text(rest)
					if display:lower() == match:lower() or rest:lower() == match:lower() then
						table.insert(exact_hits, entry)
					end
				end
			end
		end
	end
	if #exact_hits > 0 then
		return exact_hits
	end
	return hits
end

--- Insert a checklist line under an optional heading and/or parent task.
--- opts: text, link, status, heading, parent_lnum, parent_match.
--- @return integer|nil lnum, table info
M.insert_task = function(lines, opts)
	opts = opts or {}
	local tasks_shared = require("notes.shared.tasks")

	local box = opts.box or tasks_shared.status_box(opts.status or "todo")
	if not box then
		return nil, { error = "status must be one of: todo, doing, waiting, done" }
	end

	local rest = vim.trim(opts.text or "")
	local link = opts.link and M.clean_link(opts.link):gsub("%.md$", "") or ""
	if link ~= "" then
		if rest == "" then
			rest = "[[ " .. link .. " ]]"
		elseif not rest:find("%[%[", 1, true) then
			rest = rest .. " [[ " .. link .. " ]]"
		end
	end
	if rest == "" then
		return nil, { error = "text or link is required" }
	end

	local insert_at, indent = #lines + 1, ""
	local parent_line = nil

	if opts.parent_lnum or (opts.parent_match and opts.parent_match ~= "") or (opts.parent_link and opts.parent_link ~= "") then
		local hits, err = M.find_task_lines(lines, {
			heading = opts.heading,
			lnum = opts.parent_lnum,
			match = opts.parent_match,
			link = opts.parent_link,
		})
		if not hits then
			return nil, err
		end
		if #hits == 0 then
			return nil, { error = "no parent task line matched" }
		end
		if #hits > 1 then
			return nil, {
				error = "parent match is ambiguous, matched " .. #hits .. " task lines; retry with parent_lnum",
				candidates = hits,
			}
		end

		local parent = hits[1]
		parent_line = parent.line
		local parent_indent = parent.line:match("^(%s*)") or ""
		indent = parent_indent .. "  "
		insert_at = parent.lnum + 1

		-- Land after the parent's existing children, not between them.
		for i = parent.lnum + 1, #lines do
			local parsed = tasks_shared.parse_task_line(lines[i])
			if parsed and #parsed.indent > #parent_indent then
				insert_at = i + 1
			elseif vim.trim(lines[i]) == "" then
				-- Blank lines inside a child block are skipped.
			else
				break
			end
		end
	elseif opts.heading and opts.heading ~= "" then
		local heading_lnum, headings = M.find_heading(lines, opts.heading)
		if not heading_lnum then
			return nil, {
				error = "heading not found: " .. tostring(opts.heading),
				headings = headings,
			}
		end
		insert_at = M.section_end(lines, heading_lnum) + 1
		while insert_at > heading_lnum + 1 and vim.trim(lines[insert_at - 1]) == "" do
			insert_at = insert_at - 1
		end
	end

	local line = indent .. "- [" .. box .. "] " .. rest
	table.insert(lines, insert_at, line)

	return insert_at, {
		line = line,
		indent = indent,
		parent = parent_line,
	}
end

-- ── Git helpers (synchronous) ───────────────────────────────────────────
-- notes.git's helpers are callback-based (built for the interactive UI);
-- an MCP tool handler must return synchronously, so history/diff tools use
-- these blocking equivalents instead of requiring notes.git.

--- Run a git command against the notes directory and block for the result.
--- @param args string[] Arguments after `git -C <notes_dir>`.
--- @return boolean ok, string|nil stdout, string|nil stderr
M.run_git_sync = function(args)
	if vim.fn.executable("git") ~= 1 then
		return false, nil, "git not found"
	end
	local cmd = { "git", "-C", M.notes_dir }
	for _, a in ipairs(args) do
		table.insert(cmd, a)
	end
	local obj = vim.system(cmd, { text = true }):wait()
	return obj.code == 0, obj.stdout, obj.stderr
end

--- True when the notes directory is (already) inside a git work tree.
M.is_git_repo = function()
	local ok = M.run_git_sync({ "rev-parse", "--is-inside-work-tree" })
	return ok
end

--- Path of `abs_path` relative to the notes directory, or nil when it lives
--- outside it. The separator is part of the check, so a sibling directory that
--- merely shares a prefix (`/v/notes-old/x.md` vs `/v/notes`) is not a hit.
--- @param abs_path string
--- @return string|nil
M.relative_path = function(abs_path)
	local prefix = M.notes_dir .. "/"
	if abs_path:sub(1, #prefix) ~= prefix then
		return nil
	end
	local rel = abs_path:sub(#prefix + 1)
	return rel ~= "" and rel or nil
end

return M
