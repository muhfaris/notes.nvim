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
	hl(0, "NotesHomeHeadRecent", { fg = "#7aa2f7", bold = true })
	hl(0, "NotesHomeHeadTasks", { fg = "#9ece6a", bold = true })
	hl(0, "NotesHomeHeadActions", { fg = "#bb9af7", bold = true })
	hl(0, "NotesHomeRecentBody", { fg = "#9aa5ce" })
	hl(0, "NotesHomeTaskBody", { fg = "#c0caf5" })
	hl(0, "NotesHomeMuted", { fg = "#565f89" })
end

-- ── Section builders ─────────────────────────────────────────────────

local function section_header(title)
	return { "", "   " .. title, "   " .. string.rep("─", 46) }
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

local function build_tasks_section()
	local lines = section_header("📝 Open Tasks & TODOs")

	local config = require("notes.config").get_config()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	local tasks = require("notes.shared.tasks").scan(notes_dir)

	if #tasks > 0 then
		local labels = { task = "☐", todo = "TODO", ask = "ASK", ["#todo"] = "#todo", ["#tech-debt"] = "#debt" }
		for i = 1, math.min(10, #tasks) do
			table.insert(lines, string.format("   %s  %s", labels[tasks[i].type] or tasks[i].type, tasks[i].text))
		end
	else
		table.insert(lines, "   (no open tasks 🎉)")
	end
	return lines, tasks
end

-- ── Render ────────────────────────────────────────────────────────────

function M.render(buf)
	local recent_lines, recent_entries = build_recent_section(require("notes.recent").read())
	local lines = {}
	local action_map = {}

	lines[#lines + 1] = "   " .. string.rep("─", 66)
	lines[#lines + 1] = "   📚  Notes Home"
	lines[#lines + 1] = "   " .. string.rep("─", 66)
	for _, l in ipairs(recent_lines) do
		lines[#lines + 1] = l
	end

	local task_lines, tasks = build_tasks_section()
	for _, l in ipairs(task_lines) do
		lines[#lines + 1] = l
	end

	-- Record absolute line numbers so <CR> can open the note.
	-- Recently Modified entries start with "•", task entries are tracked in the
	-- "Open Tasks" region. Both are keyed by the rendered line number.
	local in_recent = false
	local in_tasks = false
	local recent_idx = 0
	local task_idx = 0
	for idx, l in ipairs(lines) do
		if l:match("📌 Recently Modified") then
			in_recent = true
		elseif l:match("📝 Open Tasks") then
			in_recent = false
			in_tasks = true
		elseif l:match("🚀 Quick Actions") then
			in_tasks = false
		end

		if in_recent and l:match("^%s+•%s") then
			recent_idx = recent_idx + 1
			local e = recent_entries[recent_idx]
			if e and e.path then
				action_map[tostring(idx)] = { path = e.path }
			end
		elseif in_tasks and l:match("^%s+[☐T#]%S*%s") then
			task_idx = task_idx + 1
			local t = tasks[task_idx]
			if t then
				action_map[tostring(idx)] = { path = t.path, lnum = t.lnum }
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
		elseif l:match("📌 Recently Modified") then
			g = "NotesHomeHeadRecent"
		elseif l:match("📝 Open Tasks") then
			g = "NotesHomeHeadTasks"
		elseif l:match("🚀 Quick Actions") then
			g = "NotesHomeHeadActions"
		elseif l:match("^%s+[☐T#]%s") or l:match("no open tasks") then
			g = "NotesHomeTaskBody"
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

	-- <CR> on a recent or task entry opens that note in a new split.
	vim.keymap.set("n", "<CR>", function()
		local cur = vim.api.nvim_win_get_cursor(0)[1]
		local ok, map = pcall(vim.json.decode, vim.g.notes_home_actions or "{}")
		local entry = ok and map ~= nil and map[tostring(cur)] or nil
		if entry and entry.path then
			vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(entry.path))
			if entry.lnum and entry.lnum > 0 then
				vim.cmd("call cursor(" .. entry.lnum .. ", 0)")
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
