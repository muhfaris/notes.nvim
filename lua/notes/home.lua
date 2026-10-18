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
	hl(0, "NotesHomeHeadWaiting", { fg = "#ff9e64", bold = true })
	hl(0, "NotesHomeHeadWeek", { fg = "#9ece6a", bold = true })
	hl(0, "NotesHomeHeadActions", { fg = "#bb9af7", bold = true })
	hl(0, "NotesHomeRecentBody", { fg = "#9aa5ce" })
	hl(0, "NotesHomePinnedBody", { fg = "#e0af68" })
	hl(0, "NotesHomeTaskBody", { fg = "#c0caf5" })
	hl(0, "NotesHomeDoingBody", { fg = "#7dcfff" })
	hl(0, "NotesHomeWaitingBody", { fg = "#ff9e64" })
	hl(0, "NotesHomeAskBody", { fg = "#bb9af7" })
	hl(0, "NotesHomeMuted", { fg = "#565f89" })
	hl(0, "NotesHomeScope", { fg = "#565f89" })
	hl(0, "NotesHomeGroupHeader", { fg = "#7aa2f7", italic = true })
end

-- ── Section builders ─────────────────────────────────────────────────
-- Every builder returns `lines` plus `meta`, a map from 1-based local line
-- index to { hl = <highlight group>, action = <what <CR> opens> } — `action`
-- entries are exactly the shape vim.g.notes_home_actions carries. render()
-- offsets both into absolute line numbers, so a section is never recognised
-- again by re-matching its own rendered text: that match broke once two
-- sections shared a glyph, and would have broken again telling a `⏳ Waiting`
-- lane header apart from a `⏳` card.

local function section_header(lines, meta, title, hl)
	table.insert(lines, "")
	table.insert(lines, "   " .. title)
	table.insert(lines, "   " .. string.rep("─", 46))
	meta[#lines - 1] = { hl = hl }
end

local function is_truthy(v)
	v = tostring(v or ""):lower()
	return v == "true" or v == "1" or v == "yes"
end

local function truncate(text, width)
	if #text <= width then
		return text
	end
	return text:sub(1, width - 1) .. "…"
end

--- "3h ago" for a file mtime. A pinned card exists to be *current*, so it
--- states how long since the board it summarises was touched.
local function rel_age(epoch)
	if not epoch or epoch == 0 then
		return "unknown"
	end
	local d = os.time() - epoch
	if d < 3600 then
		return math.max(1, math.floor(d / 60)) .. "m ago"
	elseif d < 86400 then
		return math.floor(d / 3600) .. "h ago"
	end
	return math.floor(d / 86400) .. "d ago"
end

--- Headings in a board are prose, and some carry a wikilink
--- (`### Wednesday [[Daily Note: 2026-09-09]]`) or a typo (`### Thrusday`).
--- Strip a trailing link for display; fall back to the raw heading when
--- nothing survives, so the author's own label is never lost.
local function heading_label(raw)
	local clean = vim.trim((raw:gsub("%s*%[%[.-%]%]%s*$", "")))
	return clean ~= "" and clean or raw
end

--- Read one board's checklist lines, each tagged with the heading it sits
--- under, whether it is still open, and whether it is a *leaf* — an open item
--- whose next checklist sibling is not indented deeper. Leaves are "the work
--- I can actually do"; containers are the categories. Board order is priority
--- order, so nothing is sorted here.
local function board_entries(path, notes_dir)
	local tasks = require("notes.shared.tasks")
	local entries = {}
	local heading = "(top)"
	for i, line in ipairs(vim.fn.readfile(path)) do
		local h = line:match("^#+%s+(.+)$")
		if h then
			heading = heading_label(h)
		else
			local parsed = tasks.parse_task_line(line)
			if parsed then
				table.insert(entries, {
					lnum = i,
					line = line,
					indent = parsed.indent or "",
					box = parsed.box,
					status = tasks.box_status(parsed.box),
					open = tasks.is_open_box(parsed.box),
					text = tasks.display_task_text(parsed.rest or ""),
					heading = heading,
				})
			end
		end
	end
	for i, entry in ipairs(entries) do
		local nxt = entries[i + 1]
		entry.leaf = not (nxt and #nxt.indent > #entry.indent)
		if entry.open then
			entry.detail = tasks.detail_path_from_line(path, entry.line, notes_dir)
		end
	end
	return entries
end

--- Pinned notes are the watchlist, newest first. With nothing pinned we fall
--- back to the newest note under a `tasks/` path (flagged `fell_back`) rather
--- than rendering an empty dashboard to a first-time user.
local function collect_boards(notes_dir)
	local pinned, fallback = {}, {}
	for _, note_path in ipairs(vim.fn.globpath(notes_dir, "**/*.md", false, true)) do
		local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
		if rel_path:sub(1, 10) ~= "templates/" and vim.fn.filereadable(note_path) == 1 then
			local metadata = require("notes.parser").read_file(note_path)
			if metadata then
				local note = {
					path = note_path,
					title = (metadata.title ~= "" and metadata.title)
						or vim.fn.fnamemodify(note_path, ":t:r"),
					date = metadata.date or "",
				}
				if is_truthy(metadata.pinned) then
					table.insert(pinned, note)
				elseif rel_path:match("^tasks/") or rel_path:match("/tasks/") then
					table.insert(fallback, note)
				end
			end
		end
	end
	local by_date = function(a, b)
		return (a.date or "") > (b.date or "")
	end
	table.sort(pinned, by_date)
	local boards, fell_back = pinned, false
	if #boards == 0 and #fallback > 0 then
		table.sort(fallback, by_date)
		boards, fell_back = { fallback[1] }, true
	end
	for _, b in ipairs(boards) do
		b.entries = board_entries(b.path, notes_dir)
		b.mtime = vim.fn.getftime(b.path)
		b.open, b.next = 0, 0
		for _, e in ipairs(b.entries) do
			if e.open then
				b.open = b.open + 1
				if e.leaf then
					b.next = b.next + 1
				end
			end
		end
	end
	return boards, fell_back
end

-- ── The scope line ───────────────────────────────────────────────────
-- States what the dashboard is scoped to, so the difference between the 26
-- "next" items here and a vault-wide `:Notes tasks` count is never a mystery.
local function build_scope_section(boards, fell_back)
	local lines, meta = {}, {}
	local open, nexts = 0, 0
	for _, b in ipairs(boards) do
		open = open + b.open
		nexts = nexts + b.next
	end
	local label
	if #boards == 0 then
		label = "no pinned notes"
	elseif fell_back then
		label = "1 board (nothing pinned)"
	else
		label = string.format("%d pinned", #boards)
	end
	table.insert(
		lines,
		string.format(
			"   scope: %s · %d open · %d next   ·   vault-wide lives in `:Notes tasks`",
			label,
			open,
			nexts
		)
	)
	meta[#lines] = { hl = "NotesHomeScope" }
	return lines, meta
end

local MAX_CARDS = 8
local NEXT_PER_CARD = 3

-- ── 📌 Pinned watchlist ────────────────────────────────────────────────
-- Each pinned note is a *live card* — its open/next counts and how long since
-- it was touched — followed by its next few leaves. A title-only list says
-- nothing about state, which defeats the reason for pinning it.
local function build_pinned_section(boards)
	local lines, meta = {}, {}
	section_header(lines, meta, "📌 Pinned watchlist", "NotesHomeHeadPinned")
	if #boards == 0 then
		table.insert(lines, "   (nothing pinned yet — add `pinned: true` to a note)")
		meta[#lines] = { hl = "NotesHomeMuted" }
		return lines, meta
	end
	for i = 1, math.min(MAX_CARDS, #boards) do
		local b = boards[i]
		table.insert(
			lines,
			string.format("   📌 %s   ·  %d open · %d next · updated %s", b.title, b.open, b.next, rel_age(b.mtime))
		)
		meta[#lines] = { hl = "NotesHomePinnedBody", action = { path = b.path } }
		local shown = 0
		for _, e in ipairs(b.entries) do
			if e.open and e.leaf and shown < NEXT_PER_CARD then
				shown = shown + 1
				table.insert(lines, "        ▸ " .. truncate(e.text, 46))
				meta[#lines] = {
					hl = "NotesHomeTaskBody",
					action = { path = e.detail or b.path, lnum = e.detail and nil or e.lnum },
				}
			end
		end
		if b.open == 0 then
			table.insert(lines, "        · nothing open — the watchlist is clear")
			meta[#lines] = { hl = "NotesHomeMuted" }
		end
	end
	return lines, meta
end

-- ── 🗓  This Week ─────────────────────────────────────────────────────
-- The newest board's open leaves under the board's own day headings, in board
-- order. Reusing the author's own structure — instead of re-inventing one —
-- is what made variant A win the prototype.
local function build_week_section(boards)
	local lines, meta = {}, {}
	if #boards == 0 then
		return lines, meta
	end
	local board = boards[1]
	section_header(lines, meta, "🗓  This Week — " .. board.title, "NotesHomeHeadWeek")
	local heading = nil
	local shown = 0
	for _, e in ipairs(board.entries) do
		if e.open and e.leaf then
			if e.heading ~= heading then
				heading = e.heading
				table.insert(lines, "   " .. heading)
				meta[#lines] = { hl = "NotesHomeGroupHeader" }
			end
			shown = shown + 1
			table.insert(lines, "     ▸ " .. truncate(e.text, 52))
			meta[#lines] = {
				hl = "NotesHomeTaskBody",
				action = { path = e.detail or board.path, lnum = e.detail and nil or e.lnum },
			}
		end
	end
	if shown == 0 then
		table.insert(lines, "   (nothing open this week)")
		meta[#lines] = { hl = "NotesHomeMuted" }
	end
	return lines, meta
end

local function build_recent_section(recent)
	local lines, meta = {}, {}
	section_header(lines, meta, "📌 Recently Modified", "NotesHomeHeadRecent")
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
			meta[#lines] = { hl = "NotesHomeRecentBody", action = { path = e.path } }
			count = count + 1
		end
	end
	if count == 0 then
		table.insert(lines, "   (no recent notes yet — open or save one to track it)")
		meta[#lines] = { hl = "NotesHomeMuted" }
	end
	return lines, meta
end

local BOARD_ORDER = { "doing", "waiting", "todo", "ask", "misc" }
local BOARD_LABEL = {
	doing = "🔁 In Progress",
	waiting = "⏳ Waiting on someone",
	todo = "📝 Todo",
	ask = "❓ Ask",
	misc = "🔖 TODO / tags",
}
local BOARD_GLYPH = { doing = "◐", waiting = "⏳", todo = "☐", ask = "ASK", misc = "◦" }
local BOARD_HEAD_HL = {
	doing = "NotesHomeHeadTasks",
	waiting = "NotesHomeHeadWaiting",
	todo = "NotesHomeHeadTasks",
	ask = "NotesHomeHeadTasks",
	misc = "NotesHomeHeadTasks",
}
local BOARD_BODY_HL = {
	doing = "NotesHomeDoingBody",
	waiting = "NotesHomeWaitingBody",
	todo = "NotesHomeTaskBody",
	ask = "NotesHomeAskBody",
	misc = "NotesHomeTaskBody",
}

-- Buckets: cards (checkbox `task`s carrying status) plus type-groups for the
-- non-checkbox inline markers so each kanban lane keeps only its own kind.
-- `waiting` is a checklist status like doing/todo, so it is bucketed by status
-- before the `ask` type-group: an inline `ASK:` marker is a different thing
-- from a checklist line parked on somebody else's reply.
local function bucket_tasks(tasks)
	local out = { doing = {}, waiting = {}, todo = {}, ask = {}, misc = {} }
	for _, t in ipairs(tasks) do
		if t.status == "doing" then
			table.insert(out.doing, t)
		elseif t.status == "waiting" then
			table.insert(out.waiting, t)
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
-- weekly board's "Workstream") appears many indistinguishable times.
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

-- Draw one vertical lane block: a header, one sub-header per source note,
-- and each note's card rows. Shows every entry (no cap) — a lane answers
-- "what is still pending in the pinned boards", so silently truncating would
-- hide real open work.
local function emit_lane(lines, meta, lane, entries)
	table.insert(lines, "")
	table.insert(lines, "   " .. BOARD_LABEL[lane] .. " (" .. #entries .. ")")
	meta[#lines] = { hl = BOARD_HEAD_HL[lane] }
	table.insert(lines, "   " .. string.rep("─", 46))
	if #entries == 0 then
		table.insert(lines, "   (none)")
		meta[#lines] = { hl = "NotesHomeMuted" }
		return
	end
	for _, group in ipairs(group_by_note(entries)) do
		table.insert(lines, "     ▸ " .. group.title)
		meta[#lines] = { hl = "NotesHomeGroupHeader" }
		for _, entry in ipairs(group.items) do
			table.insert(lines, string.format("         %s  %s", BOARD_GLYPH[lane], entry.text))
			meta[#lines] = {
				hl = BOARD_BODY_HL[lane],
				action = {
					path = entry.path,
					lnum = entry.lnum,
					detail = entry.detail,
					status = entry.status,
				},
			}
		end
	end
end

-- Lanes, scoped to the boards the watchlist is built from. A vault-wide scan
-- already has a home (`:Notes tasks`, the notes_tasks MCP tool), and a lane
-- that mixes detail-note prose into Todo cannot answer "what is still
-- pending" — which is what this dashboard exists for.
local function build_tasks_section(notes_dir, boards)
	local lines, meta = {}, {}

	local board_paths = {}
	for _, b in ipairs(boards) do
		board_paths[b.path] = true
	end

	local scoped = {}
	for _, t in ipairs(require("notes.shared.tasks").scan(notes_dir)) do
		if board_paths[t.path] then
			table.insert(scoped, t)
		end
	end

	if #scoped == 0 then
		section_header(lines, meta, "📝 Open Tasks & TODOs", "NotesHomeHeadTasks")
		table.insert(lines, "   (no open tasks in the pinned boards 🎉)")
		meta[#lines] = { hl = "NotesHomeMuted" }
		return lines, meta
	end

	local buckets = bucket_tasks(scoped)
	for _, lane in ipairs(BOARD_ORDER) do
		emit_lane(lines, meta, lane, buckets[lane])
	end
	return lines, meta
end

-- ── Render ────────────────────────────────────────────────────────────

function M.render(buf)
	local config = require("notes.config").get_config()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")

	local lines, meta = {}, {}
	local hl_by_line = {}
	local action_map = {}

	-- Merge a section's local meta into absolute line numbers; `action` keys are
	-- the line numbers <CR> and the p/x/b/w keys look up.
	local function append(section_lines, section_meta)
		local offset = #lines
		for _, l in ipairs(section_lines) do
			table.insert(lines, l)
		end
		for li, m in pairs(section_meta or {}) do
			local abs = offset + li
			if m.action then
				action_map[tostring(abs)] = m.action
			end
			if m.hl then
				hl_by_line[abs] = m.hl
			end
		end
	end

	local function bare(text, hl)
		table.insert(lines, text)
		hl_by_line[#lines] = hl
	end

	bare("   " .. string.rep("─", 66), "NotesHomeSep")
	bare("   📚  Notes Home", "NotesHomeTitle")
	bare("   " .. string.rep("─", 66), "NotesHomeSep")

	local boards, fell_back = {}, false
	if notes_dir ~= "" then
		boards, fell_back = collect_boards(notes_dir)
	end

	append(build_scope_section(boards, fell_back))
	append(build_pinned_section(boards))
	append(build_week_section(boards))
	append(build_recent_section(require("notes.recent").read()))
	if notes_dir ~= "" then
		append(build_tasks_section(notes_dir, boards))
	end

	bare("", "NotesHomeSep")
	bare("   🚀 Quick Actions", "NotesHomeHeadActions")
	bare("   " .. string.rep("─", 46), "NotesHomeSep")
	bare("   [n] new   [d] daily   [s] search   [r] refresh   [t] tasks", "NotesHomeMuted")
	bare("   [p] promote   [w] waiting   [x] done   [b] back to todo   [q] close", "NotesHomeMuted")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.g.notes_home_actions = vim.json.encode(action_map) or "{}"

	-- Apply per-line highlights from the same meta the sections built.
	ensure_highlights()
	local ns = vim.api.nvim_create_namespace("notes_home")
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i = 1, #lines do
		vim.api.nvim_buf_add_highlight(buf, ns, hl_by_line[i] or "NotesHomeMuted", i - 1, 0, -1)
	end
end

-- ── Open / toggle ─────────────────────────────────────────────────────

-- Close Notes Home. Closing the last window raises E444, so when Home is the
-- only window we clear its `bufhidden` and swap in a clean empty buffer
-- instead: the window survives and the dashboard buffer is wiped.
function M.close(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.fn.winnr("$") == 1 then
		vim.api.nvim_set_option_value("bufhidden", "", { buf = buf })
		vim.cmd("enew")
	else
		vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
	end
end

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
		M.close(home_buf)
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

	-- Checklist grammar (box <-> status, the box rewriter, the detail-note sync)
	-- is owned by notes.shared.tasks, so these keys and the notes_toggle_task MCP
	-- tool cannot drift on which glyph means what.
	local tasks_shared = require("notes.shared.tasks")

	-- Best-effort: mirrors notes_toggle_task's detail-note sync so a status
	-- change reads the same whether it came from these keys or from an AI
	-- agent using the MCP tool.
	local function sync_detail_status(path, fixed_line, status)
		local config = require("notes.config").get_config()
		local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
		tasks_shared.sync_detail_status(path, fixed_line, notes_dir, status)
	end

	-- Rewrite the checkbox box on the target note line: if the markdown buffer is
	-- already open we edit it in place and save it (so unsaved edits aren't lost),
	-- otherwise we read/modify/write the file on disk. `status` is the target
	-- state name ("todo"/"doing"/"waiting"/"done"); the glyph it writes comes
	-- from notes.shared.tasks.status_box, so `x` cannot mean one thing here and
	-- another in the MCP tool.
	local function persist_card(status)
		local box = tasks_shared.status_box(status)
		if not box then
			return false
		end
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
			local fixed = tasks_shared.set_box(line, box)
			if fixed ~= line then
				vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { fixed })
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("silent write")
				end)
				sync_detail_status(path, fixed, status)
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
				local fixed = tasks_shared.set_box(l, box)
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
			sync_detail_status(path, fixed_line, status)
			M.render(home_buf)
			return true
		end
		return false
	end
	-- Movement keys act on cards, and name the *target status* rather than a
	-- glyph: p promotes todo, w parks it on somebody else's reply, x finishes
	-- doing, b sends it back to todo. The written box comes from the shared
	-- grammar. `b` also accepts a waiting card, so waiting is never a dead end.
	vim.keymap.set("n", "p", function()
		local e = hovered_card()
		if e and e.status == "todo" then
			persist_card("doing")
		end
	end, opts)
	vim.keymap.set("n", "w", function()
		local e = hovered_card()
		if e and (e.status == "todo" or e.status == "doing") then
			persist_card("waiting")
		end
	end, opts)
	vim.keymap.set("n", "x", function()
		local e = hovered_card()
		if e and e.status == "doing" then
			persist_card("done")
		end
	end, opts)
	vim.keymap.set("n", "b", function()
		local e = hovered_card()
		if e and (e.status == "doing" or e.status == "waiting") then
			persist_card("todo")
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
