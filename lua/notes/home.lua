-- lua/notes/home.lua
--- A dedicated "Notes Home" floating window showing recent activity,
--- incomplete tasks, and quick actions. Reads MRU state from notes.recent
--- and task scanning from notes.ui.list_tasks internals.

local M = {}

local HOME_BUF = "notes://home"

-- Highlight groups used by the Notes Home dashboard.
local HIGHLIGHTS_DEFINED = false
local function ensure_highlights()
	if HIGHLIGHTS_DEFINED then
		return
	end
	HIGHLIGHTS_DEFINED = true
	local hl = vim.api.nvim_set_hl
	hl(0, "NotesHomeTitle", { fg = "#fabd2f", bold = true })
	hl(0, "NotesHomeSep", { fg = "#3a3a3a" })
	hl(0, "NotesHomeHeadPinned", { fg = "#e0af68", bold = true })
	hl(0, "NotesHomeHeadRecent", { fg = "#7aa2f7", bold = true })
	hl(0, "NotesHomeHeadTasks", { fg = "#9ece6a", bold = true })
	hl(0, "NotesHomeHeadActions", { fg = "#bb9af7", bold = true })
	hl(0, "NotesHomeRecentBody", { fg = "#9aa5ce" })
	hl(0, "NotesHomePinnedBody", { fg = "#e0af68" })
	hl(0, "NotesHomeTaskBody", { fg = "#c0caf5" })
	hl(0, "NotesHomeDoingBody", { fg = "#7dcfff" })
	hl(0, "NotesHomeAskBody", { fg = "#bb9af7" })
	hl(0, "NotesHomeMuted", { fg = "#565f89" })
	hl(0, "NotesHomeGroupHeader", { fg = "#7aa2f7", italic = true })
end

-- ── Section builders ─────────────────────────────────────────────────

local function section_header(title)
	return { "", "   " .. title, "   " .. string.rep("─", 46) }
end

local function is_truthy(v)
	v = tostring(v or ""):lower()
	return v == "true" or v == "1" or v == "yes"
end

local function build_pinned_section()
	local lines = section_header("📌 Pinned")

	local config = require("notes.config").get_config()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	if notes_dir == "" then
		table.insert(lines, "   (no notes directory configured)")
		return lines, {}
	end

	local files = vim.fn.globpath(notes_dir, "**/*.md", false, true)
	local pinned = {}
	for _, note_path in ipairs(files) do
		if vim.fn.filereadable(note_path) == 1 then
			local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
			if rel_path:sub(1, 10) ~= "templates/" then
				local metadata = require("notes.parser").read_file(note_path)
				if metadata and is_truthy(metadata.pinned) then
					table.insert(pinned, {
						path = note_path,
						title = (metadata.title ~= "" and metadata.title) or vim.fn.fnamemodify(note_path, ":t:r"),
						date = metadata.date or "",
						tags = metadata.tags or {},
					})
				end
			end
		end
	end

	table.sort(pinned, function(a, b)
		return (a.date or "") > (b.date or "")
	end)

	local displayed = {}
	for i = 1, math.min(8, #pinned) do
		local e = pinned[i]
		local date = (e.date or ""):sub(1, 10)
		local tags = type(e.tags) == "table" and #e.tags > 0 and ("[" .. table.concat(e.tags, ", ") .. "]") or ""
		table.insert(lines, string.format("   %s  %s  %s  %s", "📌", date, tags, e.title))
		table.insert(displayed, e)
	end
	if #pinned == 0 then
		table.insert(lines, "   (nothing pinned yet — add `pinned: true` to a note)")
	end
	return lines, displayed
end

local function build_recent_section(recent)
	local lines = section_header("📌 Recently Modified")
	local displayed = {}
	local count = 0
	for _, e in ipairs(recent) do
		if count >= 8 then
			break
		end
		if vim.fn.filereadable(e.path) == 1 then
			local date = (e.date or ""):sub(1, 10)
			local tags = type(e.tags) == "table" and #e.tags > 0 and ("[" .. table.concat(e.tags, ", ") .. "]") or ""
			-- persist() only stores the bare filename; resolve the real title.
			local title = e.title
			local metadata = require("notes.parser").read_file(e.path)
			if metadata and metadata.title and metadata.title ~= "" then
				title = metadata.title
			end
			table.insert(lines, string.format("   %s  %s  %s  %s", "•", date, tags, title))
			table.insert(displayed, e)
			count = count + 1
		end
	end
	if count == 0 then
		table.insert(lines, "   (no recent notes yet — open or save one to track it)")
	end
	return lines, displayed
end

local BOARD_ORDER = { "doing", "todo", "ask", "misc" }
local BOARD_LABEL = {
	doing = "🔁 In Progress",
	todo = "📝 Todo",
	ask = "❓ Ask",
	misc = "🔖 TODO / tags",
}
local BOARD_GLYPH = { doing = "◐", todo = "☐", ask = "ASK", misc = "◦" }

-- Buckets: cards (checkbox `task`s carrying status) plus type-groups for the
-- non-checkbox inline markers so each kanban lane keeps only its own kind.
local function bucket_tasks(tasks)
	local out = { doing = {}, todo = {}, ask = {}, misc = {} }
	for _, t in ipairs(tasks) do
		if t.status == "doing" then
			table.insert(out.doing, t)
		elseif t.status == "todo" then
			table.insert(out.todo, t)
		elseif t.type == "ask" then
			table.insert(out.ask, t)
		else
			table.insert(out.misc, t)
		end
	end
	return out
end

-- Group entries by their source note, newest source note first — same
-- "recent first" principle as the daily-note completion sort — so a lane
-- reads as "here's each note with open work, most recently touched first"
-- instead of one flat list where the same recurring category name (e.g. a
-- weekly board's "Batas Komplain") appears many indistinguishable times.
local function group_by_note(entries)
	local groups, order = {}, {}
	for _, e in ipairs(entries) do
		local g = groups[e.path]
		if not g then
			local metadata = require("notes.parser").read_file(e.path)
			local title = (metadata and metadata.title and metadata.title ~= "") and metadata.title
				or vim.fn.fnamemodify(e.path, ":t:r")
			g = { title = title, date = (metadata and metadata.date) or "", items = {} }
			groups[e.path] = g
			table.insert(order, g)
		end
		table.insert(g.items, e)
	end
	table.sort(order, function(a, b)
		return (a.date or "") > (b.date or "")
	end)
	return order
end

-- Draw one vertical lane block appending a header, one sub-header per source
-- note, and each note's card rows into `lines`. Each card row records its
-- absolute (local) line index in `idx_act`. Shows every entry (no cap) —
-- this is meant to answer "what's pending across the whole vault," so
-- silently truncating would hide real open work.
local function emit_lane(lines, idx_act, title, glyph, entries)
	table.insert(lines, "")
	table.insert(lines, "   " .. title .. " (" .. #entries .. ")")
	table.insert(lines, "   " .. string.rep("─", 46))
	if #entries == 0 then
		table.insert(lines, "   (none)")
		return
	end
	for _, group in ipairs(group_by_note(entries)) do
		table.insert(lines, "     ▸ " .. group.title)
		for _, entry in ipairs(group.items) do
			table.insert(lines, string.format("         %s  %s", glyph, entry.text))
			idx_act[#lines] = { path = entry.path, lnum = entry.lnum, detail = entry.detail, status = entry.status }
		end
	end
end

local function build_tasks_section()
	local lines = {}
	local idx_act = {}

	local config = require("notes.config").get_config()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	local tasks = require("notes.shared.tasks").scan(notes_dir)
	local buckets = bucket_tasks(tasks)
	if #tasks == 0 then
		for _, l in ipairs(section_header("📝 Open Tasks & TODOs")) do
			table.insert(lines, l)
		end
		table.insert(lines, "   (no open tasks 🎉)")
		return lines, idx_act
	end

	for _, lane in ipairs(BOARD_ORDER) do
		emit_lane(lines, idx_act, BOARD_LABEL[lane], BOARD_GLYPH[lane], buckets[lane])
	end
	return lines, idx_act
end

-- ── Render ────────────────────────────────────────────────────────────

function M.render(buf)
	local recent_lines, recent_entries = build_recent_section(require("notes.recent").read())
	local lines = {}
	local action_map = {}

	lines[#lines + 1] = "   " .. string.rep("─", 66)
	lines[#lines + 1] = "   📚  Notes Home"
	lines[#lines + 1] = "   " .. string.rep("─", 66)

	local pinned_lines, pinned_entries = build_pinned_section()
	for _, l in ipairs(pinned_lines) do
		lines[#lines + 1] = l
	end

	for _, l in ipairs(recent_lines) do
		lines[#lines + 1] = l
	end

	local task_lines, task_idx_act = build_tasks_section()
	local task_offset = #lines + 1 -- first line index of the lane block
	for _, l in ipairs(task_lines) do
		lines[#lines + 1] = l
	end
	for li, a in pairs(task_idx_act) do
		action_map[tostring(task_offset + li - 1)] = a
	end

	-- Record absolute line numbers so <CR> can open the note for pinned and
	-- recent rows (task/lane rows were already merged from task_idx_act above).
	local in_pinned = false
	local in_recent = false
	local pinned_idx = 0
	local recent_idx = 0
	local PINNED_HEADER = "📌 Pinned"
	for idx, l in ipairs(lines) do
		if l:match("📌 Pinned$") then
			in_pinned = true
			in_recent = false
		elseif l:match("📌 Recently Modified") then
			in_pinned = false
			in_recent = true
		elseif l:match("🔁 In Progress") or l:match("📝 Todo") or l:match("❓ Ask") or l:match("🔖 TODO") or l:match("🚀 Quick Actions") then
			in_pinned = false
			in_recent = false
		end

		if in_pinned and l ~= "   " .. PINNED_HEADER and l:match("^%s+📌%s") then
			pinned_idx = pinned_idx + 1
			local e = pinned_entries[pinned_idx]
			if e and e.path then
				action_map[tostring(idx)] = { path = e.path }
			end
		elseif in_recent and l:match("^%s+•%s") then
			recent_idx = recent_idx + 1
			local e = recent_entries[recent_idx]
			if e and e.path then
				action_map[tostring(idx)] = { path = e.path }
			end
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "   🚀 Quick Actions"
	lines[#lines + 1] = "   " .. string.rep("─", 46)
	lines[#lines + 1] = "   [n] new   [d] daily   [s] search   [r] refresh   [t] tasks   [q] close"

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.g.notes_home_actions = vim.json.encode(action_map) or "{}"

	-- Apply per-line highlights.
	ensure_highlights()
	local ns = vim.api.nvim_create_namespace("notes_home")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, l in ipairs(lines) do
		local g = "NotesHomeMuted"
		if i == 2 then
			g = "NotesHomeTitle"
		elseif l:match("^%s*📌 Pinned") then
			g = "NotesHomeHeadPinned"
		elseif l:match("📌 Recently Modified") then
			g = "NotesHomeHeadRecent"
		elseif l:match("🔁 In Progress") or l:match("📝 Todo") or l:match("❓ Ask") or l:match("🔖 TODO") or l:match("📝 Open Tasks") or l:match("no open tasks") then
			g = "NotesHomeHeadTasks"
		elseif l:match("🚀 Quick Actions") then
			g = "NotesHomeHeadActions"
		elseif l:match("^%s+◐%s") then
			g = "NotesHomeDoingBody"
		elseif l:match("^%s+ASK%s") then
			g = "NotesHomeAskBody"
		elseif l:match("^%s+[☐◦]%s") then
			g = "NotesHomeTaskBody"
		elseif l:match("^%s+▸%s") then
			g = "NotesHomeGroupHeader"
		elseif l:match("^%s+📌%s") then
			g = "NotesHomePinnedBody"
		elseif l:match("^%s+•%s") then
			g = "NotesHomeRecentBody"
		end
		vim.api.nvim_buf_add_highlight(buf, ns, g, i - 1, 0, -1)
	end
end

-- ── Open / toggle ─────────────────────────────────────────────────────

function M.open()
	-- Toggle off if already shown (search existing windows like the explorer does).
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf_win = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf_win)
		if name:match(HOME_BUF) then
			vim.api.nvim_win_close(win, true)
			return
		end
	end

	-- Decide the hosting window:
	--   * If the current window is still the empty/startup buffer (welcome state),
	--     reuse it in place so Home acts like a welcome/home screen.
	--   * Otherwise open Home in a brand-new tab page.
	local cur_buf = vim.api.nvim_get_current_buf()
	local cur_name = vim.api.nvim_buf_get_name(cur_buf)
	local cur_buftype = vim.bo[cur_buf].buftype
	local empty_state = cur_name == ""
		and (cur_buftype == "" or cur_buftype == nil)
		and vim.bo[cur_buf].modified == false

	if empty_state then
		vim.cmd("enew") -- ensure a clean unnamed buffer in the current window
	else
		vim.cmd("tabnew")
	end

	-- Find an existing Home buffer, or create one, then show it in the window.
	local home_buf = nil
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name:match(HOME_BUF) then
			home_buf = buf
			break
		end
	end

	if not home_buf then
		home_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(home_buf, HOME_BUF)
	end
	vim.api.nvim_win_set_buf(0, home_buf)

	vim.api.nvim_set_option_value("buftype", "nofile", { buf = home_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = home_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = home_buf })
	vim.api.nvim_set_option_value("filetype", "noteshome", { buf = home_buf })
	vim.api.nvim_set_option_value("wrap", false, { win = 0 })
	vim.api.nvim_set_option_value("number", false, { win = 0 })
	vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = 0 })

	M.render(home_buf)

	local opts = { buffer = home_buf, silent = true, noremap = true }

	-- Close key removes the Home window.
	vim.keymap.set("n", "q", function()
		local w = vim.api.nvim_get_current_win()
		if vim.fn.winnr("$") == 1 then
			-- Last window: replace Home with a clean empty buffer instead of closing.
			vim.api.nvim_set_option_value("bufhidden", "", { buf = home_buf })
			vim.cmd("enew")
		else
			vim.api.nvim_win_close(w, true)
		end
	end, opts)

	-- Action keys run a command from within Home.
	vim.keymap.set("n", "n", function()
		require("notes.ui").new_note()
	end, opts)
	vim.keymap.set("n", "d", function()
		require("notes.ui").daily_note()
	end, opts)
	vim.keymap.set("n", "s", function()
		require("notes.ui").search_notes()
	end, opts)
	vim.keymap.set("n", "t", function()
		require("notes.ui").list_tasks()
	end, opts)
	vim.keymap.set("n", "r", function()
		M.render(home_buf) -- refresh in place
	end, opts)

	-- Return the hovered lane card (only checkbox cards carry a status + lnum).
	local function hovered_card()
		local cur = vim.api.nvim_win_get_cursor(0)[1]
		local ok, map = pcall(vim.json.decode, vim.g.notes_home_actions or "{}")
		local entry = ok and map ~= nil and map[tostring(cur)] or nil
		if entry and entry.status and entry.lnum then
			return entry
		end
		return nil
	end

	-- box -> notes.shared.tasks status name, for detail-note sync below.
	local BOX_STATUS = { [" "] = "todo", ["/"] = "doing", ["x"] = "done" }

	-- Best-effort: mirrors notes_toggle_task's detail-note sync so a status
	-- change reads the same whether it came from these keys or from an AI
	-- agent using the MCP tool.
	local function sync_detail_status(path, fixed_line, box)
		local status = BOX_STATUS[box]
		if not status then
			return
		end
		local config = require("notes.config").get_config()
		local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
		require("notes.shared.tasks").sync_detail_status(path, fixed_line, notes_dir, status)
	end

	-- Rewrite the checkbox box on the target note line: if the markdown buffer is
	-- already open we edit it in place and save it (so unsaved edits aren't lost),
	-- otherwise we read/modify/write the file on disk. `box` is the raw marker
	-- text without brackets e.g. "/", "x", or a single space (for `[ ]`).
	local function persist_card(box)
		local e = hovered_card()
		if not e then
			return false
		end
		local path, lnum = e.path, e.lnum
		local buf = vim.fn.bufnr(path)
		if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
			local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
			if not line then
				return false
			end
			local fixed = line:gsub("(%s*[-*]%s*%[)([^)%]])(%])", "%1" .. box .. "%3", 1)
			if fixed ~= line then
				vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { fixed })
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("silent write")
				end)
				sync_detail_status(path, fixed, box)
				M.render(home_buf)
			end
			return true
		end

		local f = io.open(path, "r")
		if not f then
			return false
		end
		local content = f:read("*a")
		f:close()
		local n = 0
		local changed = false
		local fixed_line = nil
		local out = {}
		for _, l in ipairs(vim.split(content, "\n")) do
			n = n + 1
			if n == lnum then
				local fixed = l:gsub("(%s*[-*]%s*%[)([^]])(%])", "%1" .. box .. "%3", 1)
				if fixed ~= l then
					changed = true
					fixed_line = fixed
					l = fixed
				end
			end
			table.insert(out, l)
		end
		if not changed then
			return false
		end
		local fw = io.open(path, "w")
		if fw then
			fw:write(table.concat(out, "\n"))
			fw:close()
			sync_detail_status(path, fixed_line, box)
			M.render(home_buf)
			return true
		end
		return false
	end
	-- Movement keys act on the todo/doing lanes only.
	vim.keymap.set("n", "p", function()
		local e = hovered_card()
		if e and e.status == "todo" then
			persist_card("/")
		end
	end, opts)
	vim.keymap.set("n", "x", function()
		local e = hovered_card()
		if e and e.status == "doing" then
			persist_card("x")
		end
	end, opts)
	vim.keymap.set("n", "b", function()
		local e = hovered_card()
		if e and e.status == "doing" then
			persist_card(" ")
		end
	end, opts)

	-- <CR> on a recent or task entry opens that note in a new split. Tasks that
	-- carry a linked detail note open the detail (the source is one hop back via
	-- its source_note frontmatter or <C-o>).
	vim.keymap.set("n", "<CR>", function()
		local cur = vim.api.nvim_win_get_cursor(0)[1]
		local ok, map = pcall(vim.json.decode, vim.g.notes_home_actions or "{}")
		local entry = ok and map ~= nil and map[tostring(cur)] or nil
		if entry then
			local target = (entry.detail and entry.detail ~= "") and entry.detail or entry.path
			if target then
				vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(target))
				if entry.detail == nil and entry.lnum and entry.lnum > 0 then
					vim.cmd("call cursor(" .. entry.lnum .. ", 0)")
				end
			end
		end
	end, opts)

	-- Re-render on WinEnter so the dashboard stays current.
	local group = vim.api.nvim_create_augroup("NotesHomeRefresh", { clear = true })
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		buffer = home_buf,
		callback = function()
			M.render(home_buf)
		end,
	})
end

return M
