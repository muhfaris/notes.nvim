--- Task detail-notes: generate an ordinary markdown note for the *detail* of
--- a task / subtask and emit a literal wiki-link back onto its checkbox line.
---
--- Convention (locked with the user):
---   * A subtask input is the subtask's *title*, not a summary.
---   * A checklist line carries its detail-note link as a single Obsidian-style
---     wikilink `[[ parent/child ]]`, padded with one space inside the
---     brackets, and *without* an alias — the `parent/child` body is what
---     resolution (M.resolve_detail_link, notes_backlinks) matches against, so
---     the line carries no separate plain-text title duplicated beside the
---     link:
---         - [ ] Login Module
---           - [ ] [[ Login Module/Fixing code oauth ]]
---   * An alias (`[[ parent/child|shorter label ]]`) is a *supported
---     alternative*, not a legacy format: `render_child_line` emits the
---     un-aliased form by default, but a hand-written alias keeps its own
---     label as the line's display text and still resolves to the same detail
---     note. The readers (M.parent_from_line, shared.tasks.display_task_text,
---     notes_backlinks, ui.resolve_wiki_link_target) strip it before resolving.
---   * The detail note is an ordinary markdown file under
---     <notes_dir>/tasks/<yyyy>/<mm>/<yyyy-mm-dd>-<slug>.md , storing the
---     child in `title` plus a `parent` frontmatter reference.
---
--- Two layers, kept separable:
---   * Headless helpers never prompt, so other code paths can reuse them.
---   * `insert_subtask()` is the interactive action run from a note buffer.

local M = {}

local utils = require("notes.utils")
local config = require("notes.config").get_config()
-- The checklist-line grammar lives in notes.shared.tasks (one pattern, one box
-- map) so this module and the MCP tools cannot drift on what a task line is.
local tasks_shared = require("notes.shared.tasks")

-- Detail notes live in a date-sharded "tasks" subtree, grouped like dailies.
M.rel_dir = "tasks"

-- Absolute, trailing-slash-trimmed notes root.
local function notes_root()
	return vim.fn.fnamemodify(vim.fn.expand(config.notes_dir), ":p"):gsub("/+$", "")
end

-- Resolve the current buffer's absolute path only when it lives in notes_dir.
local function active_note_path()
	local name = vim.api.nvim_buf_get_name(0)
	name = vim.fn.resolve(name)
	local root = vim.fn.resolve(vim.fn.expand(config.notes_dir))
	if name == "" or name:sub(1, #root) ~= root then
		return nil
	end
	return name
end

-- Sanitized id/slug for a subtask title.
M.slug = function(title)
	return utils.sanitize_title(title)
end


-- Date-sharded relative on-disk path for a subtask detail note, e.g.
-- "tasks/2026/09/2026-09-05-fixing-code-oauth".
M.file_rel = function(title)
	local date = tostring(os.date(config.date_format or "%Y-%m-%d"))
	local yyyy, mm, dd = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	local slug = M.slug(title)
	if yyyy and mm and dd and slug and slug ~= "" then
		return string.format("%s/%s/%s/%s-%s-%s-%s", M.rel_dir, yyyy, mm, yyyy, mm, dd, slug)
	end
	if slug and slug ~= "" then
		local base = tostring(os.date(config.date_format or "%Y-%m-%d")):gsub("[^%w%-]", "-")
		return string.format("%s/%s-%s", M.rel_dir, base, slug)
	end
	return M.rel_dir
end

-- The wiki-link body printed on the child checkbox line. When a parent title
-- is given it reads as `parent/child`; otherwise it is just the child title.
M.link_body = function(child_title, parent_title)
	local child = vim.trim(child_title or "")
	local parent = vim.trim(parent_title or "")
	if parent ~= "" and child ~= "" then
		return parent .. "/" .. child
	end
	return child
end

-- Absolute on-disk path for a title's detail note.
M.target_path = function(title)
	local rel = M.file_rel(title)
	if rel == M.rel_dir then
		return nil
	end
	return notes_root() .. "/" .. rel .. ".md"
end


-- Write the detail note for a subtask title if it does not already exist.
-- Pure on args, never prompts, never overwrites an existing file.
-- Returns the absolute path written, or the existing path, or nil; and a
-- second boolean: true when a new file was written, false when an
-- already-existing note (same day, same title slug) was reused instead --
-- distinguishing the two matters to a caller like notes_add_subtask, since a
-- silent reuse can mean two different subtasks under different parents just
-- got linked to the same shared note.
M.ensure_detail_note = function(title, opts)
	opts = opts or {}
	title = vim.trim(title or "")
	if title == "" then
		return nil, false
	end

	local full_path = M.target_path(title)
	if not full_path then
		return nil, false
	end
	if vim.fn.filereadable(full_path) == 1 then
		return full_path, false
	end

	local dir = vim.fn.fnamemodify(full_path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end

	local date = tostring(os.date(config.date_format or "%Y-%m-%d"))
	local time = tostring(os.date(config.time_format or "%H:%M:%S"))
	local esc = title:gsub('"', '\\"')
	local parent = vim.trim(opts.parent or "")
	local source = opts.source or active_note_path()

	local lines = {
		"---",
		'title: "' .. esc .. '"',
		'date: "' .. date .. " " .. time .. '"',
		'tags: ["task"]',
	}
	if parent ~= "" then
		-- The parent reference matches the hierarchy link printed on the task.
		table.insert(lines, 'parent: "[[ ' .. vim.trim(parent:gsub('"', '\\"')) .. ' ]]"')
	end

	if source then
		local root = vim.fn.resolve(vim.fn.expand(config.notes_dir))
		local rel_src = source:gsub("^" .. vim.pesc(root .. "/"), "")
		table.insert(lines, 'source_note: "' .. rel_src .. '"')
	end
	table.insert(lines, "---")
	table.insert(lines, "# " .. title)
	table.insert(lines, "")
	table.insert(lines, "## Notes")

	local f = io.open(full_path, "w")
	if not f then
		return nil, false
	end
	f:write(table.concat(lines, "\n"))
	f:close()
	return full_path, true
end

-- Render the text of a child checkbox line pointing at a detail note, as a
-- single un-aliased wikilink `[[ parent/child ]]` (see the file-level
-- convention comment) rather than a plain-text title duplicated next to the
-- link. The body already ends in the child title, so the generated line never
-- carries an alias -- an alias stays available as a hand-written alternative
-- when a line should read differently from the child title.
M.render_child_line = function(child_title, parent_title, indentation)
	local body = M.link_body(child_title, parent_title)
	if body == "" then
		return nil
	end
	return string.format("%s- [ ] [[ %s ]]", indentation or "", body)
end


-- Pull the human title out of a task list line: the text following a
-- `- [ ]` / `- [x]` / `- [/]` etc. marker, dropping any trailing inline `[[...]]`
-- detail link and leading indentation. Returns nil when there is no recognizable
-- title left.
--
-- A line may carry NO plain text at all beside its link — our own
-- render_child_line writes `- [ ] [[ parent/child ]]` with nothing before the
-- bracket, which matters when nesting a subtask under an already-linked child
-- line. That fallback (the `|alias`, else the last `/`-segment of
-- `parent/child`) is owned by notes.shared.tasks.display_task_text, so this
-- function and Home's kanban cards can never disagree about which label wins.
M.parent_from_line = function(line)
	local parsed = tasks_shared.parse_task_line(line)
	local text = vim.trim(tasks_shared.display_task_text(parsed and parsed.rest or (line or "")))
	return text ~= "" and text or nil
end

-- True when a line is a checklist item carrying a known box (`- [ ]`, `* [/]`,
-- any indent). Delegates to the shared predicate so this module, the Home
-- dashboard and the MCP tools answer the question identically.
M.is_task_line = function(line)
	return tasks_shared.is_task_line(line)
end


-- ── Interactive insert ─────────────────────────────────────────────────

-- Insert a nested child for the task under the cursor: write the detail note,
-- then place a linked checkbox one level deeper beneath the current line.
-- Safe no-op when the cursor is not on a task line.
M.insert_subtask = function()
	local cur_line = vim.api.nvim_get_current_line()
	if not M.is_task_line(cur_line) then
		vim.notify("Notes: place the cursor on a task (checklist) line first", vim.log.levels.WARN)
		return false
	end

	local parent_title = M.parent_from_line(cur_line)
	vim.ui.input({ prompt = "Subtask title (creates a child detail note): " }, function(title)
		title = vim.trim(title or "")
		if title == "" then
			return
		end
		local note_path = M.ensure_detail_note(title, { parent = parent_title })
		if not note_path then
			vim.notify("Notes: could not write the detail note", vim.log.levels.ERROR)
			return
		end

		local parent_line = vim.api.nvim_get_current_line()
		local indent = (parent_line:match("^(%s*)") or "") .. "  "
		local text = M.render_child_line(title, parent_title, indent)
		if not text then
			return
		end

		local cur = vim.api.nvim_win_get_cursor(0)
		local row = cur[1] -- 1-based current line
		vim.api.nvim_buf_set_lines(0, row, row, false, { text })
		vim.api.nvim_win_set_cursor(0, { row, #indent + #"- [ ] " })
		vim.notify("Subtask linked: [[ " .. M.link_body(title, parent_title) .. "]]", vim.log.levels.INFO)
	end)
	return true
end

return M
