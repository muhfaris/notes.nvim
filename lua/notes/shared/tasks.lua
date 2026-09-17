-- lua/notes/shared/tasks.lua
--- Shared task detection across notes: scans notes for incomplete checklist
--- items, inline TODO/ASK markers, and #todo / #tech-debt tags. Used by the
--- Telescope task picker (ui.lua) and the home dashboard (home.lua) so the
--- detection logic lives in one place.

local M = {}

-- Sort order across task types (lower sorts first)
M.order = { task = 1, todo = 2, ask = 3, ["#todo"] = 4, ["#tech-debt"] = 5 }

-- Checkbox states for a `task` entry. Scan emits only not-started (`[ ]`) and
-- in-progress (`[/]` or `[~]`); done (`[x]`/`[X]`) never becomes a card.
M.statuses = { todo = "todo", doing = "doing" }

--- Match an inline TODO/ASK-style marker at the start of the line
--- (`- KEYWORD: text` or `KEYWORD: text`) or at the end (`text :KEYWORD`),
--- case-insensitive. Anchoring to the line's start or end — rather than
--- matching the keyword anywhere with just a colon nearby — is what keeps
--- this from misfiring on prose that merely contains the word mid-sentence
--- (e.g. "I'd ask: ..." or "...with todo sign...") or inside another word
--- ("MASK:"). Returns the marker's text payload, or nil if line has none.
--- @param line string
--- @param keyword string Upper-case keyword, e.g. "TODO" or "ASK".
--- @return string|nil
local function match_marker(line, keyword)
	local upper = line:upper()

	-- "- KEYWORD: text" / "KEYWORD: text" — keyword opens the line.
	local _, e = upper:find("^%s*[-*]?%s*" .. keyword .. "%s*:%s*")
	if e then
		return vim.trim(line:sub(e + 1))
	end

	-- "text :KEYWORD" — keyword closes the line.
	local s = upper:find(":%s*" .. keyword .. "%s*$")
	if s then
		return vim.trim((line:sub(1, s - 1):gsub("^%s*[-*]%s*", "")))
	end

	return nil
end

--- Strip a trailing `[[...]]` detail link from a checklist line's text so
--- Home's kanban cards and the notes_tasks MCP tool show a readable label
--- instead of raw wikilink syntax. Our own subtask.lua writes checklist
--- lines as a single un-aliased link with nothing else beside it
--- (`- [ ] [[ parent/child ]]`), so when stripping the link leaves nothing
--- behind, fall back to the link's `|alias` (legacy aliased links), or its
--- last `/`-segment (the child part of `parent/child`). That segment is only
--- a guess — M.scan overrides it with the resolved detail note's own title
--- when one exists, which is what keeps a child title containing a `/`
--- intact.
--- @param rest string Line text after the `- [ ]`/`[x]`/`[/]` marker.
--- @return string
M.display_task_text = function(rest)
	local link_body = rest:match("%[%[%s*(.-)%s*%]%]%s*$")
	local text = vim.trim((rest:gsub("%s*%[%[[^%]]*%]%]%s*$", "")))
	if text ~= "" then
		return text
	end
	if link_body then
		local alias = link_body:match("|%s*(.-)%s*$")
		if alias and alias ~= "" then
			return alias
		end
		local child = vim.trim((link_body:gsub("|.*$", ""):match("([^/]+)%s*$") or ""))
		if child ~= "" then
			return child
		end
	end
	return vim.trim(rest)
end

--- Resolve the trailing [[...]] detail link on a task line to an existing
--- markdown path. Our generated subtask links are anchored to the notes
--- root (e.g. tasks/2026/09/2026-09-05-<slug>), so root-relative is tried
--- first, then relative to the containing note's folder, then falls back to
--- matching the link's last `/`-segment as a subtask title (see
--- M.resolve_detail_link). Exposed at module level (not just used by M.scan)
--- so other callers, e.g. the notes_toggle_task MCP tool, can resolve a
--- single task line's detail note without re-scanning the whole vault.
--- @param note_path string Absolute path of the note containing the line.
--- @param line string The raw task line text.
--- @param notes_dir string Absolute notes root.
--- @return string|nil Absolute path of the resolved detail note, or nil.
M.detail_path_from_line = function(note_path, line, notes_dir)
	notes_dir = notes_dir:gsub("/+$", "")
	local start = 1
	local link = nil
	while true do
		local s, e, body = line:find("%[%[([^%]]+)%]%]", start)
		if not s then
			break
		end
		body = (body or ""):gsub("[|#].*$", ""):gsub("\\", "/") -- strip alias/anchor, normalize slash
		body = vim.trim(body)
		link = body
		start = e + 1
	end
	if not link or link == "" then
		return nil
	end
	local norm = link:gsub("^/+", ""):gsub("/+$", "")
	if norm == "" then
		return nil
	end
	local note_root = vim.fn.fnamemodify(note_path, ":h")
	local candidates = {
		notes_dir .. "/" .. norm,
		notes_dir .. "/" .. norm .. ".md",
		note_root .. "/" .. norm,
		note_root .. "/" .. norm .. ".md",
	}
	for _, c in ipairs(candidates) do
		if vim.fn.filereadable(c) == 1 then
			return c
		end
	end
	-- Fall back: match the last `/`-segment against subtask titles stored
	-- under the notes-root tasks subtree (human `parent/child` bodies).
	return M.resolve_detail_link(link, notes_dir)
end

--- Scan all notes under notes_dir and return the collected tasks.
--- @param notes_dir string Absolute path to the notes directory.
--- @return table[] tasks Sorted task entries: { path, title, lnum, text, line, type, status?, detail? }
--- Where checklist `task` entries also carry `status` ("todo"|"doing").
M.scan = function(notes_dir)
	notes_dir = notes_dir:gsub("/+$", "")
	local files = vim.fn.globpath(notes_dir, "**/*.md", false, true)
	local tasks = {}

	for _, note_path in ipairs(files) do
		local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
		if rel_path:sub(1, 10) ~= "templates/" then
			local file = io.open(note_path, "r")
			if file then
				local lnum = 1
				local title = vim.fn.fnamemodify(note_path, ":t:r")
				local metadata = require("notes.parser").read_file(note_path)
				if metadata and metadata.title and metadata.title ~= "" then
					title = metadata.title
				end

				local function push(type_, text, line, status, rest)
					if text and text ~= "" then
						local entry = {
							path = note_path,
							title = title,
							lnum = lnum,
							text = text,
							line = line,
							type = type_,
						}
						if status then
							entry.status = status
						end
						-- For checkbox tasks, expose a linked detail note so Home and the
						-- task picker can jump into it directly.
						if type_ == "task" then
							local stripped = line:gsub("%[%[[^%]]+%]%]", ""):gsub("%s+$", "")
							if stripped:find("- [", 1, true) ~= nil then
								entry.detail = M.detail_path_from_line(note_path, line, notes_dir)
								-- A link-only label (`- [ ] [[ parent/child ]]`) is ambiguous by
								-- construction: the child title may itself contain a `/`, so the
								-- last-segment guess in display_task_text can truncate it. When
								-- the detail note resolved, its own title is the ground truth.
								local link_only = vim.trim((rest or ""):gsub("%s*%[%[[^%]]*%]%]%s*$", "")) == ""
								if entry.detail and link_only then
									local md = require("notes.parser").read_file(entry.detail)
									if md and md.title and md.title ~= "" then
										entry.text = md.title
									end
								end
							end
						end
						table.insert(tasks, entry)
					end
				end

				for line in file:lines() do
					-- 1. Checkbox task. Capture the box char: ` ` -> todo,
					--    `/` or `~` -> in-progress; any other (x/X) skipped.
					local boxchar, rest = line:match("^%s*[-*]%s*%[(.)%](.*)$")
					if boxchar then
						local text = M.display_task_text(rest:gsub("^%s+", ""))
						if boxchar == " " and text ~= "" then
							push("task", text, line, "todo", rest)
						elseif (boxchar == "/" or boxchar == "~") and text ~= "" then
							push("task", text, line, "doing", rest)
						end
					end

					-- 2. Inline TODO marker: "- TODO: text" / "TODO: text" / "text :todo"
					local todo_text = match_marker(line, "TODO")
					if todo_text then
						push("todo", todo_text, line)
					end

					-- 3. Inline ASK marker: "- ASK: text" / "ASK: text" / "text :ask"
					local ask_text = match_marker(line, "ASK")
					if ask_text then
						push("ask", ask_text, line)
					end

					-- 4. #todo tag
					if line:match("#todo") then
						push("#todo", vim.trim(line), line)
					end

					-- 5. #tech-debt tag
					if line:match("#tech%-debt") then
						push("#tech-debt", vim.trim(line), line)
					end

					lnum = lnum + 1
				end
				file:close()
			end
		end
	end

	table.sort(tasks, function(a, b)
		local ao = M.order[a.type] or 99
		local bo = M.order[b.type] or 99
		if ao ~= bo then
			return ao < bo
		end
		return (a.title or ""):lower() < (b.title or ""):lower()
	end)

	return tasks
end


-- Resolve a wiki-link body (e.g. "Login Module/Fixing code oauth") to an
-- existing note path. First the standard path candidates (root or containing
-- folder) are tried; if none match we fall back to matching a subtask
-- *title* against detail notes stored under `<notes_dir>/tasks/**`, by
-- checking whether the link body ENDS WITH that title (preferring the
-- longest matching title) rather than naively splitting on the last `/` —
-- a child title may itself contain `/` (e.g. "Fix A/B testing bug"), in
-- which case the true title is longer than whatever follows the final
-- slash, and a naive last-segment split would look for the wrong,
-- truncated title. Returns nil when nothing matches.
-- @param body string The wiki-link body (may include a `parent/child` path).
-- @param notes_dir string Absolute notes root.
M.resolve_detail_link = function(body, notes_dir)
	notes_dir = notes_dir:gsub("/+$", "")
	if not body then
		return nil
	end
	local norm = body:gsub("[|#].*$", ""):gsub("\\", "/")
	norm = vim.trim(norm):gsub("^/+$", ""):gsub("/+$", "")
	norm = norm:gsub("^/+", "")
	if norm == "" then
		return nil
	end
	local norm_lower = norm:lower()

	local parser = require("notes.parser")
	local files = vim.fn.globpath(notes_dir .. "/tasks", "**/*.md", false, true)
	if #files == 0 then
		return nil
	end

	local best, best_len = nil, -1
	for _, f in ipairs(files) do
		local md = parser.read_file(f)
		if md and md.title and md.title ~= "" then
			local title_lower = md.title:lower()
			local is_match = norm_lower == title_lower
				or norm_lower:sub(-(#title_lower + 1)) == "/" .. title_lower
			if is_match and (#title_lower > best_len or (#title_lower == best_len and (not best or f > best))) then
				-- Equal-length ties: later path sorts greatest (earlier fixture
				-- prefixes; on daily rotation newest wins), keeping resolution
				-- deterministic.
				best = f
				best_len = #title_lower
			end
		end
	end
	return best
end

--- Best-effort: if a task line links to a detail note (notes.subtask's
--- convention), stamp that note's own `status` frontmatter to match. Shared
--- by the notes_toggle_task MCP tool and notes.home's persist_card so a
--- status change behaves identically whether it comes from an AI agent or
--- from the interactive Home dashboard.
--- @param note_path string Absolute path of the note containing the line.
--- @param line string The task line (after its checkbox was changed).
--- @param notes_dir string Absolute notes root.
--- @param status string New status value to write ("todo"|"doing"|"done").
--- @return string|nil detail_path, boolean synced
M.sync_detail_status = function(note_path, line, notes_dir, status)
	local detail_path = M.detail_path_from_line(note_path, line, notes_dir)
	if not detail_path then
		return nil, false
	end
	local parser = require("notes.parser")
	local metadata, body = parser.read_file(detail_path)
	if not metadata then
		return detail_path, false
	end
	metadata.status = status
	local f = io.open(detail_path, "w")
	if not f then
		return detail_path, false
	end
	f:write(parser.format_frontmatter(metadata) .. "\n" .. (body or ""))
	f:close()
	return detail_path, true
end

return M
