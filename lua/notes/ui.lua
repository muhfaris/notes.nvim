-- lua/notes/ui.lua
local M = {}
local config = require("notes.config").get_config()
local utils = require("notes.utils")
local parser = require("notes.parser")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")

local EXPLORER_BUF_NAME = "notes://explorer"
local copied_note_path = nil

local function attach_markview(bufnr)
	-- markview.nvim handles its own rendering via autocmds
	-- This function is kept for backwards compatibility
end
M.attach_markview = attach_markview

-- Compute the Neovim swap filename for a given filepath.
local function get_swap_filepath(filepath)
	if not vim.o.swapfile then
		return nil
	end
	local encoded = filepath:gsub("[/\\]", "%%")
	for _, dir in ipairs(vim.split(vim.o.directory, ",", { plain = true })) do
		local clean_dir = vim.fs.normalize(dir):gsub("[/\\]+$", "")
		local swap_name = clean_dir .. "/" .. encoded .. ".swp"
		if vim.fn.filereadable(swap_name) == 1 then
			return swap_name
		end
	end
	return nil
end

-- Checks if a swap file exists for filepath and prompts the user using vim.fn.confirm.
-- Called upfront in open_note_buffer to avoid low-level bufload E325 errors.
local function check_swap_recovery(filepath)
	if not vim.o.swapfile then
		return "open"
	end

	local notes_dir = vim.fs.normalize(config.notes_dir or "")
	if notes_dir ~= "" and filepath:sub(1, #notes_dir) ~= notes_dir then
		return "open"
	end

	local swap_name = get_swap_filepath(filepath)
	if not swap_name then
		return "open"
	end

	local prompt = string.format("Swap file detected for %s", vim.fn.fnamemodify(filepath, ":t"))
	local choices_str = "&Recover\n&Edit anyway\n&Delete swap\n&Quit"
	local idx = vim.fn.confirm(prompt, choices_str, 1, "Question")

	if idx == 1 then
		return "recover"
	elseif idx == 2 or idx == 3 then
		vim.fn.delete(swap_name)
		return "open"
	else
		return "quit"
	end
end

-- Helper to open a note buffer based on the editor_style setting (current vs float)
local function open_note_buffer(filepath, target_line)
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	local buf

	local swap_action = check_swap_recovery(filepath)
	if swap_action == "quit" then
		return
	end

	if ext ~= "md" then
		-- Non-markdown assets (e.g. images): force wipe + reload so snacks.image triggers
		if swap_action == "recover" then
			vim.cmd("edit " .. vim.fn.fnameescape(filepath))
			buf = vim.api.nvim_get_current_buf()
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		else
			buf = vim.fn.bufadd(filepath)
			if vim.api.nvim_buf_is_loaded(buf) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
				buf = vim.fn.bufadd(filepath)
			end
			vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
			vim.fn.bufload(buf)
		end
	elseif config.editor_style == "current" then
		if swap_action == "recover" then
			vim.cmd("recover " .. vim.fn.fnameescape(filepath))
		else
			vim.cmd("edit " .. vim.fn.fnameescape(filepath))
		end
		buf = vim.api.nvim_get_current_buf()
	else
		-- float/tab/split/vsplit: bypass :edit to avoid wiping the current buffer
		if swap_action == "recover" then
			vim.cmd("edit " .. vim.fn.fnameescape(filepath))
			buf = vim.api.nvim_get_current_buf()
			pcall(vim.cmd, "recover")
		else
			buf = vim.fn.bufadd(filepath)
			vim.fn.bufload(buf)
		end
	end

	vim.b[buf].notes_editor = true

	vim.bo[buf].swapfile = true

	-- Register buffer-local autocommand to enforce wrapping and breakindent options
	-- whenever the notes buffer is displayed in a window.
	local au_group = vim.api.nvim_create_augroup("NotesOptions_" .. buf, { clear = true })
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = au_group,
		buffer = buf,
		callback = function()
			local win_id = vim.fn.bufwinid(buf)
			if win_id ~= -1 then
				vim.wo[win_id].wrap = true
				vim.wo[win_id].linebreak = true
				vim.wo[win_id].breakindent = true
			end
		end,
	})

	if config.editor_style == "float" then
		-- Calculate dimensions (80% width, 80% height)
		local width = math.floor(vim.o.columns * 0.8)
		local height = math.floor(vim.o.lines * 0.8)
		if width > 120 then
			width = 120
		end
		if height > 40 then
			height = 40
		end
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		-- Create window options
		local win_opts = {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			border = "rounded",
			title = " " .. vim.fn.fnamemodify(filepath, ":t") .. " [q: save & close] ",
			title_pos = "center",
		}
		if vim.fn.has("nvim-0.9") == 1 then
			win_opts.footer = " q: close | <C-g>e: edit | <C-g>t: tab "
			win_opts.footer_pos = "center"
		end

		local win = vim.api.nvim_open_win(buf, true, win_opts)

		-- Force markview to do a complete render (workaround for partial conceal on first paint)
		if package.loaded["markview"] then
			local mv = require("markview").strict_render
			mv:clear(buf)
			mv:render(buf)
		end

		-- Wrap lines and show numbers in the floating note window
		vim.api.nvim_set_option_value("wrap", true, { win = win })
		vim.api.nvim_set_option_value("linebreak", true, { win = win })
		vim.api.nvim_set_option_value("breakindent", true, { win = win })
		vim.api.nvim_set_option_value("number", true, { win = win })
		vim.api.nvim_set_option_value("relativenumber", false, { win = win })

		-- Buffer-local shortcut 'q' to save and close the float modal
		vim.keymap.set(
			"n",
			"q",
			"<cmd>w<CR><cmd>close<CR>",
			{ buffer = buf, silent = true, desc = "Save and Close Note Float" }
		)

		-- Move to tab
		vim.keymap.set("n", "<C-g>t", function()
			vim.cmd("write")
			vim.cmd("close")
			vim.cmd("tabnew")
			vim.api.nvim_win_set_buf(0, buf)
			vim.keymap.set(
				"n",
				"q",
				"<cmd>w<CR><cmd>tabclose<CR>",
				{ buffer = buf, silent = true, desc = "Save and Close Note Tab" }
			)
		end, { buffer = buf, silent = true, desc = "Move Note from Float to Tab" })

		-- Move to editor (normal buffer)
		vim.keymap.set("n", "<C-g>e", function()
			vim.cmd("write")
			vim.cmd("close")
			vim.api.nvim_win_set_buf(0, buf)
			pcall(vim.keymap.del, "n", "q", { buffer = buf })
		end, { buffer = buf, silent = true, desc = "Move Note from Float to Editor" })
	elseif config.editor_style == "tab" then
		vim.cmd("tabnew")
		vim.api.nvim_win_set_buf(0, buf)
		vim.keymap.set(
			"n",
			"q",
			"<cmd>w<CR><cmd>tabclose<CR>",
			{ buffer = buf, silent = true, desc = "Save and Close Note Tab" }
		)
	elseif config.editor_style == "split" then
		vim.cmd("split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.keymap.set(
			"n",
			"q",
			"<cmd>w<CR><cmd>close<CR>",
			{ buffer = buf, silent = true, desc = "Save and Close Note Split" }
		)
	elseif config.editor_style == "vsplit" then
		vim.cmd("vsplit")
		vim.api.nvim_win_set_buf(0, buf)
		vim.keymap.set(
			"n",
			"q",
			"<cmd>w<CR><cmd>close<CR>",
			{ buffer = buf, silent = true, desc = "Save and Close Note Split" }
		)
	end

	vim.bo[buf].omnifunc = "v:lua.require'notes.ui'.omnifunc"

	-- Jump to target line if provided
	if target_line and target_line > 0 then
		pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
	end
end

-- Function to truncate text and add ellipsis
local function truncate(text, width)
	if #text > width then
		return text:sub(1, width - 3) .. "..."
	end
	return text
end

-- Helper to prompt user using a clean rounded floating window
local function prompt_title_popup(callback)
	local width = 50
	local height = 1
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " New Note Title ",
		title_pos = "center",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	vim.cmd("startinsert")

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		local mode = vim.api.nvim_get_mode().mode
		if mode:sub(1, 1) == "i" then
			vim.cmd("stopinsert")
		end
	end

	vim.keymap.set("i", "<CR>", function()
		local title = vim.trim(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or "")
		close()
		if title ~= "" then
			callback(title)
		else
			vim.notify("Note creation cancelled: empty title", vim.log.levels.WARN)
		end
	end, { buffer = buf, silent = true })

	local cancel = function()
		close()
		vim.notify("Note creation cancelled", vim.log.levels.INFO)
	end

	vim.keymap.set("i", "<Esc>", cancel, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, silent = true })
	vim.keymap.set("n", "q", cancel, { buffer = buf, silent = true })

	vim.api.nvim_create_autocmd("BufLeave", {
		buffer = buf,
		once = true,
		callback = cancel,
	})
end

-- Helper to create daily note structure
local function create_daily_note_at_path(full_path, dir_path, date_str)
	if vim.fn.isdirectory(dir_path) == 0 then
		vim.fn.mkdir(dir_path, "p")
	end

	local time = os.date(config.time_format)
	local title = "Daily Note: " .. date_str
	local template = (config.daily_template and config.daily_template ~= "") and config.daily_template
		or config.template
	template = template:gsub("%%TITLE%%", title)
	template = template:gsub("%%DATE%%", date_str .. " " .. time)
	template = template:gsub("tags:%s*%[%s*%]", 'tags: ["daily"]')
	template = template:gsub("%%BODY%%", "")

	local file = io.open(full_path, "w")
	if not file then
		vim.notify("Could not create daily note: " .. full_path, vim.log.levels.ERROR)
		return false
	end
	file:write(template)
	file:close()
	return true
end

-- Helper to position cursor in newly created daily note
local function position_daily_cursor()
	local task_line = vim.fn.search("^## Tasks / Notes")
	if task_line == 0 then
		task_line = vim.fn.search("^## Focus")
	end
	if task_line > 0 then
		pcall(vim.api.nvim_win_set_cursor, 0, { task_line + 2, 0 })
	end
end

-- Helper to parse date from active buffer name
local function get_current_buffer_date()
	local active_buf = vim.api.nvim_get_current_buf()
	local active_file = vim.api.nvim_buf_get_name(active_buf)
	if active_file == "" then
		return nil
	end

	active_file = vim.fn.resolve(active_file)
	local notes_dir_abs = vim.fn.resolve(config.notes_dir)

	if active_file:sub(1, #notes_dir_abs) ~= notes_dir_abs then
		return nil
	end

	local yyyy, mm, dd = active_file:match("(%d%d%d%d)/(%d%d)/(%d%d)/daily%.md$")
	if yyyy and mm and dd then
		return { year = tonumber(yyyy), month = tonumber(mm), day = tonumber(dd) }
	end

	local yyyy2, mm2, dd2 = active_file:match("daily_(%d%d%d%d)%-(%d%d)%-(%d%d)%.md$")
	if yyyy2 and mm2 and dd2 then
		return { year = tonumber(yyyy2), month = tonumber(mm2), day = tonumber(dd2) }
	end

	local yyyy3, mm3, dd3 = active_file:match("(%d%d%d%d)%-(%d%d)%-(%d%d)%.md$")
	if yyyy3 and mm3 and dd3 then
		return { year = tonumber(yyyy3), month = tonumber(mm3), day = tonumber(dd3) }
	end

	return nil
end

-- Helper to traverse to daily note
local function open_or_create_daily(target_time)
	local target_date = os.date(config.date_format, target_time)
	local yyyy, mm, dd = target_date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	local dir_path = config.notes_dir
	local filename
	if yyyy and mm and dd then
		dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
		filename = "daily.md"
	else
		filename = "daily_" .. target_date .. ".md"
	end
	local full_path = dir_path .. "/" .. filename

	if vim.fn.filereadable(full_path) == 1 then
		open_note_buffer(full_path)
		return
	end

	local legacy_path = config.notes_dir .. "/" .. target_date .. ".md"
	if vim.fn.filereadable(legacy_path) == 1 then
		open_note_buffer(legacy_path)
		return
	end

	local confirm = vim.fn.confirm("Daily note for " .. target_date .. " does not exist. Create it?", "&Yes\n&No", 1)
	if confirm == 1 then
		if create_daily_note_at_path(full_path, dir_path, target_date) then
			open_note_buffer(full_path)
			position_daily_cursor()
		end
	end
end

-- API to create a new note
M.new_note = function(title)
	local function create_note_file(input_title, template_content, directory)
		local date = os.date(config.date_format)
		local time = os.date(config.time_format)
		local sanitized_title = utils.sanitize_title(input_title)

		local dir_path
		local filename
		if directory then
			dir_path = config.notes_dir .. "/" .. directory
			filename = sanitized_title .. ".md"
		else
			local yyyy, mm, dd = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
			if yyyy and mm and dd then
				dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
				filename = sanitized_title .. ".md"
			else
				dir_path = config.notes_dir
				filename = string.format("%s_%s.md", sanitized_title, date)
			end
		end

		if vim.fn.isdirectory(dir_path) == 0 then
			vim.fn.mkdir(dir_path, "p")
		end
		local full_path = dir_path .. "/" .. filename

		local template = template_content or config.template
		template = template:gsub("%%TITLE%%", input_title)
		template = template:gsub("%%DATE%%", date .. " " .. time)
		template = template:gsub("%%BODY%%", "")

		local file = io.open(full_path, "w")
		if not file then
			vim.notify("Could not create note file: " .. full_path, vim.log.levels.ERROR)
			return
		end
		file:write(template)
		file:close()

		open_note_buffer(full_path)
		local desc_line = vim.fn.search("^## Description")
		if desc_line == 0 then
			desc_line = vim.fn.search("^## Background")
		end
		if desc_line == 0 then
			desc_line = vim.fn.search("^## Attendees")
		end
		if desc_line == 0 then
			desc_line = vim.fn.search("^## Overview")
		end
		if desc_line == 0 then
			desc_line = vim.fn.search("^## Company Profile")
		end
		if desc_line > 0 then
			pcall(vim.api.nvim_win_set_cursor, 0, { desc_line + 1, 0 })
		end
		vim.notify("Note created: " .. filename, vim.log.levels.INFO)
	end

	local function get_title_and_create(template_content, directory)
		if title and title ~= "" then
			create_note_file(title, template_content, directory)
		else
			prompt_title_popup(function(input_title)
				create_note_file(input_title, template_content, directory)
			end)
		end
	end

	local builtins = require("notes.config")._builtin_templates
	local builtin_daily = require("notes.config")._builtin_daily_template

	local all_templates = {}
	if config.templates and type(config.templates) == "table" then
		for k, v in pairs(config.templates) do
			if type(v) == "table" then
				all_templates[k] = {
					type = "config",
					content = v.content or builtins[k],
					directory = v.directory,
				}
			else
				all_templates[k] = { type = "config", content = v }
			end
		end
	end
	if config.daily_template and not all_templates.daily then
		local dt = config.daily_template
		if type(dt) == "table" then
			all_templates.daily = {
				type = "config",
				content = dt.content or builtin_daily,
				directory = dt.directory,
			}
		else
			all_templates.daily = { type = "config", content = dt }
		end
	end

	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	local templates_dir = notes_dir .. "/templates"
	if vim.fn.isdirectory(templates_dir) == 1 then
		local files = vim.fn.globpath(templates_dir, "*.md", false, true)
		for _, file_path in ipairs(files) do
			local name = vim.fn.fnamemodify(file_path, ":t:r")
			all_templates[name] = { type = "file", path = file_path }
		end
	end

	local keys = {}
	for k, _ in pairs(all_templates) do
		table.insert(keys, k)
	end
	table.sort(keys)

	local function get_template_content(name)
		local t = all_templates[name]
		if not t then
			return nil
		end
		if t.type == "config" then
			return t.content, t.directory
		elseif t.type == "file" then
			local f = io.open(t.path, "r")
			if f then
				local content = f:read("*all")
				f:close()
				return content, nil
			end
		end
		return nil
	end

	if #keys > 1 then
		pickers
			.new({}, {
				prompt_title = "Select Note Template",
				finder = finders.new_table({
					results = keys,
				}),
				sorter = conf.generic_sorter({}),
				previewer = previewers.new_buffer_previewer({
					title = "Template Preview",
					define_preview = function(self, entry, status)
						local template_name = entry.value
						local template_content = get_template_content(template_name)
						if template_content and type(template_content) == "string" then
							local lines = vim.split(template_content, "\n")
							vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
							attach_markview(self.state.bufnr)
						end
					end,
				}),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						actions.close(prompt_bufnr)
						local selection = action_state.get_selected_entry()
						if selection then
							local template_content, directory = get_template_content(selection.value)
							get_title_and_create(template_content, directory)
						end
					end)
					return true
				end,
			})
			:find()
		return
	elseif #keys == 1 then
		local content, directory = get_template_content(keys[1])
		get_title_and_create(content, directory)
		return
	end

	get_title_and_create(config.template)
end

-- API to create or open a Daily Note
M.daily_note = function()
	local date = os.date(config.date_format)
	local yyyy, mm, dd = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	local dir_path = config.notes_dir
	local filename
	if yyyy and mm and dd then
		dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
		filename = "daily.md"
	else
		filename = "daily_" .. date .. ".md"
	end
	local full_path = dir_path .. "/" .. filename

	if vim.fn.filereadable(full_path) == 1 then
		open_note_buffer(full_path)
		return
	end

	local legacy_path = config.notes_dir .. "/" .. date .. ".md"
	if vim.fn.filereadable(legacy_path) == 1 then
		open_note_buffer(legacy_path)
		return
	end

	if create_daily_note_at_path(full_path, dir_path, date) then
		open_note_buffer(full_path)
		position_daily_cursor()
		vim.notify("Daily note created: " .. filename, vim.log.levels.INFO)
	end
end

-- API to go to yesterday's daily note
M.daily_prev = function()
	local date_tbl = get_current_buffer_date()
	if not date_tbl then
		vim.notify("Not in a daily note buffer.", vim.log.levels.ERROR)
		return
	end
	local t = os.time(date_tbl)
	open_or_create_daily(t - 24 * 3600)
end

-- API to go to tomorrow's daily note
M.daily_next = function()
	local date_tbl = get_current_buffer_date()
	if not date_tbl then
		vim.notify("Not in a daily note buffer.", vim.log.levels.ERROR)
		return
	end
	local t = os.time(date_tbl)
	open_or_create_daily(t + 24 * 3600)
end

-- API to list all incomplete tasks across notes
M.list_tasks = function()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	local notes = vim.fn.globpath(notes_dir, "**/*.md", false, true)
	local tasks = {}

	for _, note_path in ipairs(notes) do
		local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
		if rel_path:sub(1, 10) ~= "templates/" then
			local file = io.open(note_path, "r")
			if file then
				local lnum = 1
				local title = vim.fn.fnamemodify(note_path, ":t:r")
				local metadata = parser.read_file(note_path)
				if metadata and metadata.title and metadata.title ~= "" then
					title = metadata.title
				end

				for line in file:lines() do
					local task_text = line:match("^%s*%- %[ %]%s*(.*)")
					if task_text and task_text ~= "" then
						table.insert(tasks, {
							path = note_path,
							title = title,
							lnum = lnum,
							text = task_text,
							line = line,
						})
					end
					lnum = lnum + 1
				end
				file:close()
			end
		end
	end

	if #tasks == 0 then
		vim.notify("No incomplete tasks found.", vim.log.levels.INFO)
		return
	end

	local displayer = entry_display.create({
		separator = " │ ",
		items = {
			{ width = 25 },
			{ width = 60 },
		},
	})

	local make_display = function(entry)
		return displayer({
			{ entry.title, "TelescopeResultsTitle" },
			{ entry.text, "TelescopeResultsNormal" },
		})
	end

	pickers
		.new({}, {
			prompt_title = "Incomplete Tasks",
			finder = finders.new_table({
				results = tasks,
				entry_maker = function(entry)
					return {
						value = entry.path,
						display = make_display,
						ordinal = entry.title .. " " .. entry.text,
						lnum = entry.lnum,
						col = 1,
						filename = entry.path,
						title = entry.title,
						text = entry.text,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry, status)
					local filepath = entry.value
					if filepath and vim.fn.filereadable(filepath) == 1 then
						local lines = vim.fn.readfile(filepath)
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
						local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
						if ext == "md" then
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
							if package.loaded["markview"] then
								vim.schedule(function()
									local mv = require("markview").strict_render
									mv:clear(self.state.bufnr)
									mv:render(self.state.bufnr)
								end)
							end
						end
					end
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						open_note_buffer(selection.value, selection.lnum)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Built-in omnifunc completion handler for wiki-links
M.omnifunc = function(findstart, base)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local col = vim.api.nvim_win_get_cursor(0)[2]
		local start = col
		while start > 0 do
			if line:sub(start - 1, start) == "[[" then
				return start
			end
			start = start - 1
		end
		return -1
	else
		local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
		local notes = vim.fn.globpath(notes_dir, "**/*.md", false, true)
		local matches = {}
		local base_lower = base:lower()

		for _, note_path in ipairs(notes) do
			local rel_path = note_path:sub(#notes_dir + 2):gsub("%.md$", ""):gsub("\\", "/")
			if rel_path:sub(1, 10) ~= "templates/" then
				local filename = vim.fn.fnamemodify(note_path, ":t:r")
				local is_daily = false
				local dy, dm, dd = note_path:match("(%d%d%d%d)/(%d%d)/(%d%d)/daily%.md$")
				if not dy then
					dy, dm, dd = note_path:match("(%d%d%d%d)%-%(%d%d)%-%(%d%d)%.md$")
				end

				local metadata = parser.read_file(note_path)

				if dy and dm and dd then
					is_daily = true
					local date_str = string.format("%s-%s-%s", dy, dm, dd)
					local title = (metadata and metadata.title and metadata.title ~= "") and metadata.title
						or ("Daily Note: " .. date_str)

					-- Suggest by pretty daily title (e.g. "Daily Note: 2026-07-14")
					if base == "" or title:lower():find(base_lower, 1, true) then
						table.insert(matches, {
							word = title .. "]]",
							abbr = title,
							menu = "[Daily Note]",
						})
					end

					-- Suggest by date (e.g. "2026-07-14")
					if base == "" or date_str:lower():find(base_lower, 1, true) then
						table.insert(matches, {
							word = title .. "]]",
							abbr = date_str,
							menu = "[Daily Date]",
						})
					end
				else
					local title = (metadata and metadata.title and metadata.title ~= "") and metadata.title or nil

					-- 1. Suggest by pretty title
					if title then
						if
							base == ""
							or title:lower():find(base_lower, 1, true)
							or filename:lower():find(base_lower, 1, true)
							or rel_path:lower():find(base_lower, 1, true)
						then
							table.insert(matches, {
								word = title .. "]]",
								abbr = title,
								menu = "[Title]",
							})
						end
					end

					-- 2. Suggest by relative path
					if
						base == ""
						or rel_path:lower():find(base_lower, 1, true)
						or filename:lower():find(base_lower, 1, true)
					then
						table.insert(matches, {
							word = (title or rel_path) .. "]]",
							abbr = rel_path,
							menu = "[Path]",
						})
					end

					-- 3. Suggest by filename (if different from rel_path and title)
					if filename ~= rel_path and (not title or filename ~= title) then
						if base == "" or filename:lower():find(base_lower, 1, true) then
							table.insert(matches, {
								word = (title or filename) .. "]]",
								abbr = filename,
								menu = "[Note]",
							})
						end
					end
				end
			end
		end
		return matches
	end
end

-- API to follow wiki-links
local function open_url(url)
	-- Validate URL before dispatching
	local trimmed = vim.trim(url or "")
	if trimmed == "" then
		return false
	end

	local scheme = trimmed:match("^([a-zA-Z][a-zA-Z0-9+%-]*)://")
	if not scheme then
		return false
	end

	if scheme == "file" then
		-- file:// protocol: open in Neovim
		local filepath = trimmed:gsub("^file://", "")
		if vim.fn.filereadable(filepath) == 1 then
			open_note_buffer(filepath)
			return true
		end
		vim.notify("File not found: " .. filepath, vim.log.levels.WARN)
		return true
	end

	-- All other protocols (http, https, ftp, mailto, etc.): open with system handler
	if vim.ui.open then
		vim.ui.open(trimmed)
	else
		local opener = "xdg-open"
		if vim.fn.has("macunix") == 1 then
			opener = "open"
		elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
			opener = "start"
		end
		vim.fn.jobstart({ opener, trimmed }, { detach = true })
	end
	vim.notify("Opening: " .. trimmed, vim.log.levels.INFO)
	return true
end

M.follow_wiki_link = function()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1

	-- First, check for standard markdown links: [text](url)
	local md_start = 1
	while true do
		local s, e, link_text, link_url = line:find("%[([^%]]-)%]%(([^)]-)%)", md_start)
		if not s then
			break
		end
		if col >= s and col <= e then
			if open_url(link_url) then
				return
			end
		end
		md_start = e + 1
	end

	-- Then check for wiki-links: [[Link]]
	local start_idx = 1
	local link_title = nil
	while true do
		local s, e, match = line:find("(%[%[[^%]]+%]%])", start_idx)
		if not s then
			break
		end
		if col >= s and col <= e then
			link_title = match:sub(3, -3)
			break
		end
		start_idx = e + 1
	end

	if not link_title or link_title == "" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
		return
	end

	-- Check if reference is a daily note date (YYYY-MM-DD or YYYY/MM/DD)
	local yyyy, mm, dd = link_title:match("^(%d%d%d%d)[%-/](%d%d)[%-/](%d%d)$")
	if not yyyy then
		yyyy, mm, dd = link_title:match("^Daily%s+Note:%s*(%d%d%d%d)[%-/](%d%d)[%-/](%d%d)$")
	end
	if yyyy and mm and dd then
		local norm_date = string.format("%s-%s-%s", yyyy, mm, dd)
		local nested_daily_path = string.format("%s/%s/%s/%s/daily.md", config.notes_dir, yyyy, mm, dd)
		local root_daily_path = config.notes_dir .. "/" .. norm_date .. ".md"

		local target_daily_path = nil
		if vim.fn.filereadable(nested_daily_path) == 1 then
			target_daily_path = nested_daily_path
		elseif vim.fn.filereadable(root_daily_path) == 1 then
			target_daily_path = root_daily_path
		end

		if target_daily_path then
			open_note_buffer(target_daily_path)
		else
			local confirm =
				vim.fn.confirm("Daily Note '" .. link_title .. "' does not exist. Create it?", "&Yes\n&No", 1)
			if confirm == 1 then
				local dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
				if vim.fn.isdirectory(dir_path) == 0 then
					vim.fn.mkdir(dir_path, "p")
				end
				local daily_path = dir_path .. "/daily.md"

				local template = config.template
				template = template:gsub("%%TITLE%%", "Daily Note: " .. norm_date)
				template = template:gsub("%%DATE%%", norm_date .. " 00:00:00")
				template = template:gsub("%%BODY%%", "")
				local file = io.open(daily_path, "w")
				if file then
					file:write(template)
					file:close()
					open_note_buffer(daily_path)
				end
			end
		end
		return
	end

	-- Priority-based general note resolution
	local normalized_link = link_title:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
	local sanitized_link = utils.sanitize_title(link_title)
	local collapsed_sanitized_link = sanitized_link:gsub("-+", "-")

	local notes = vim.fn.globpath(config.notes_dir, "**/*.md", false, true)
	local target_path = nil

	-- 1. Direct Relative/Absolute Path Match (case-insensitive)
	local direct_path = config.notes_dir .. "/" .. normalized_link
	if not direct_path:match("%.md$") then
		direct_path = direct_path .. ".md"
	end
	if vim.fn.filereadable(direct_path) == 1 then
		target_path = direct_path
	end

	-- 2. Relative Path Scan (case-insensitive)
	if not target_path then
		local link_lower = normalized_link:lower()
		for _, note in ipairs(notes) do
			local rel_path = note:sub(#config.notes_dir + 2):gsub("%.md$", ""):gsub("\\", "/")
			if rel_path:lower() == link_lower then
				target_path = note
				break
			end
		end
	end

	-- 3. Filename Match (exact or collapsed hyphens)
	if not target_path then
		for _, note in ipairs(notes) do
			local filename = vim.fn.fnamemodify(note, ":t:r")
			local collapsed_filename = filename:gsub("-+", "-")
			if
				filename:lower() == normalized_link:lower()
				or filename == sanitized_link
				or collapsed_filename == collapsed_sanitized_link
				or filename:match("^" .. vim.pesc(sanitized_link) .. "_")
			then
				target_path = note
				break
			end
		end
	end

	-- 4. Frontmatter Title Match
	if not target_path then
		for _, note in ipairs(notes) do
			local metadata = parser.read_file(note)
			if metadata and metadata.title then
				local meta_title = metadata.title
				local collapsed_meta_title = utils.sanitize_title(meta_title):gsub("-+", "-")
				if meta_title:lower() == link_title:lower() or collapsed_meta_title == collapsed_sanitized_link then
					target_path = note
					break
				end
			end
		end
	end

	if target_path then
		open_note_buffer(target_path)
	else
		local confirm = vim.fn.confirm("Note '" .. link_title .. "' does not exist. Create it?", "&Yes\n&No", 1)
		if confirm == 1 then
			local date = os.date(config.date_format)
			local time = os.date(config.time_format)

			local yyyy_now, mm_now, dd_now = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
			local dir_path = config.notes_dir
			local filename
			if yyyy_now and mm_now and dd_now then
				dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy_now, mm_now, dd_now)
				filename = sanitized_link .. ".md"
			else
				filename = string.format("%s_%s.md", sanitized_link, date)
			end

			if vim.fn.isdirectory(dir_path) == 0 then
				vim.fn.mkdir(dir_path, "p")
			end
			local full_path = dir_path .. "/" .. filename

			local template = config.template
			template = template:gsub("%%TITLE%%", link_title)
			template = template:gsub("%%DATE%%", date .. " " .. time)
			template = template:gsub("%%BODY%%", "")

			local file = io.open(full_path, "w")
			if file then
				file:write(template)
				file:close()
				open_note_buffer(full_path)
				vim.notify("Note created: " .. filename, vim.log.levels.INFO)
			else
				vim.notify("Could not create note: " .. full_path, vim.log.levels.ERROR)
			end
		end
	end
end

-- API to list notes using Telescope
-- Reusable Telescope notes list picker
local function show_notes_picker(prompt_title, results, on_delete_callback)
	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 2 }, -- Icon
			{ width = 13 }, -- Date + " -" (e.g. "2024/10/22 -")
			{ width = config.length_title }, -- Title
			{ remaining = true }, -- Tags
		},
	})

	pickers
		.new({}, {
			prompt_title = prompt_title,
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					local tags_str = #entry.tags > 0 and ("[" .. table.concat(entry.tags, ", ") .. "]") or ""

					local display_fn = function(tbl)
						local formatted_date = tbl.date:sub(1, 10):gsub("%-", "/")
						return displayer({
							{ "", "Directory" },
							{ formatted_date .. " -", "Comment" },
							{ truncate(tbl.title, config.length_title), "Normal" },
							{ tags_str ~= "" and (" " .. truncate(tags_str, 28)) or "", "Identifier" },
						})
					end

					return {
						value = entry.path,
						display = display_fn,
						ordinal = entry.title .. " " .. tags_str .. " " .. entry.date,
						title = entry.title,
						date = entry.date,
						tags = entry.tags,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry, status)
					local filepath = entry.value
					if filepath and vim.fn.filereadable(filepath) == 1 then
						local lines = vim.fn.readfile(filepath)
						vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
						local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
						if ext == "md" then
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
							if package.loaded["markview"] then
								vim.schedule(function()
									local mv = require("markview").strict_render
									mv:clear(self.state.bufnr)
									mv:render(self.state.bufnr)
								end)
							end
						end
					end
				end,
			}),
			layout_config = {
				height = 0.8,
				width = 0.9,
				preview_width = 0.6,
			},
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						open_note_buffer(selection.value)
					end
				end)

				local delete_note = function()
					local selection = action_state.get_selected_entry()
					if not selection then
						return
					end

					local note_path = selection.value
					local filename = vim.fn.fnamemodify(note_path, ":t")
					local confirm = vim.fn.confirm("Delete note '" .. filename .. "'?", "&Yes\n&No", 2)
					if confirm == 1 then
						os.remove(note_path)
						actions.close(prompt_bufnr)
						vim.notify("Note deleted: " .. filename, vim.log.levels.INFO)
						if on_delete_callback then
							on_delete_callback()
						end
					end
				end

				map("i", "<C-d>", delete_note)
				map("n", "d", delete_note)

				return true
			end,
		})
		:find()
end

-- API to list notes using Telescope
M.list_notes = function()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	local notes = vim.fn.globpath(notes_dir, "**/*.md", false, true)
	local results = {}

	for _, note_path in ipairs(notes) do
		local rel_path = note_path:sub(#notes_dir + 2):gsub("\\", "/")
		if rel_path:sub(1, 10) ~= "templates/" then
			local metadata, _ = parser.read_file(note_path)
			if metadata then
				local date = metadata.date or ""
				if date == "" then
					local mtime = vim.fn.getftime(note_path)
					date = os.date("%Y-%m-%d %H:%M:%S", mtime)
				end
				table.insert(results, {
					path = note_path,
					title = metadata.title or vim.fn.fnamemodify(note_path, ":t:r"),
					date = date,
					tags = metadata.tags or {},
					summary = metadata.summary or "",
				})
			end
		end
	end

	table.sort(results, function(a, b)
		return (a.date or "") > (b.date or "")
	end)

	show_notes_picker("Notes List", results, M.list_notes)
end

-- API to live grep content inside notes
M.search_notes = function()
	local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
	require("telescope.builtin").live_grep({
		prompt_title = "Search Note Contents",
		search_dirs = { notes_dir },
		file_ignore_patterns = { "templates/" },
	})
end

-- Helper to get the folder icon and highlight group dynamically
local function get_dir_icon(path, expanded)
	if _G.MiniIcons then
		local icon, hl = MiniIcons.get("directory", path)
		if icon then
			if not icon:match("%s$") then
				icon = icon .. " "
			end
			return icon, hl
		end
	end

	local icon = expanded and " " or " "
	return icon, "Directory"
end

-- Helper to get the file icon and highlight group dynamically
local function get_file_icon(filepath)
	local filename = vim.fn.fnamemodify(filepath, ":t")
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()

	-- Try mini.icons first
	if _G.MiniIcons then
		local icon, hl = MiniIcons.get("file", filepath)
		if icon then
			if not icon:match("%s$") then
				icon = icon .. " "
			end
			return icon, hl
		end
	end

	-- Try nvim-web-devicons
	local has_devicons, devicons = pcall(require, "nvim-web-devicons")
	if has_devicons then
		local icon, hl = devicons.get_icon(filename, ext, { default = true })
		if icon then
			if not icon:match("%s$") then
				icon = icon .. " "
			end
			return icon, hl
		end
	end

	-- Fallbacks
	if ext == "md" then
		return " ", "Special"
	elseif ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "gif" or ext == "svg" then
		return " ", "WarningMsg"
	else
		return " ", "Normal"
	end
end

-- Render the dedicated Notes Explorer dashboard
M.render_explorer = function(buf)
	local cursor = nil
	local cur_win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_get_buf(cur_win) == buf then
		cursor = vim.api.nvim_win_get_cursor(cur_win)
	end

	if not _G.notes_explorer_expanded then
		_G.notes_explorer_expanded = {}
	end

	local lines = {}
	local line_to_path = {}
	local highlight_actions = {}

	table.insert(lines, "    NOTES EXPLORER")
	table.insert(lines, "  ==================")
	table.insert(lines, "")

	table.insert(highlight_actions, { line = 0, hl = "Title", start_col = 2, end_col = -1 })
	table.insert(highlight_actions, { line = 1, hl = "Comment", start_col = 2, end_col = -1 })

	local function traverse(current_dir, depth)
		local entries = vim.fn.readdir(current_dir)
		local dirs = {}
		local files = {}
		for _, name in ipairs(entries) do
			if not name:match("^%.") then
				local abs_path = current_dir .. "/" .. name
				if vim.fn.isdirectory(abs_path) == 1 then
					local notes_dir = vim.fn.expand(config.notes_dir):gsub("/+$", "")
					if abs_path ~= notes_dir .. "/templates" then
						table.insert(dirs, { name = name, path = abs_path })
					end
				else
					local ext = name:match("%.([^%.]+)$")
					if ext then
						ext = ext:lower()
						if
							ext == "md"
							or ext == "png"
							or ext == "jpg"
							or ext == "jpeg"
							or ext == "webp"
							or ext == "gif"
							or ext == "svg"
						then
							table.insert(files, { name = name, path = abs_path })
						end
					end
				end
			end
		end

		table.sort(dirs, function(a, b)
			return a.name < b.name
		end)
		table.sort(files, function(a, b)
			return a.name < b.name
		end)

		-- Render directories
		for _, d in ipairs(dirs) do
			local indent = string.rep("  ", depth + 1)
			if _G.notes_explorer_expanded[d.path] == nil then
				_G.notes_explorer_expanded[d.path] = true
			end
			local expanded = _G.notes_explorer_expanded[d.path]

			local icon, icon_hl = get_dir_icon(d.path, expanded)
			local line_text = string.format("%s%s %s/", indent, icon, d.name)
			table.insert(lines, line_text)
			local line_idx = #lines - 1
			line_to_path[line_idx + 1] = d.path

			-- Highlight icon and directory name
			local start_col = #indent
			table.insert(
				highlight_actions,
				{ line = line_idx, hl = icon_hl or "Directory", start_col = start_col, end_col = start_col + #icon }
			)
			table.insert(
				highlight_actions,
				{ line = line_idx, hl = "Directory", start_col = start_col + #icon, end_col = -1 }
			)

			if expanded then
				traverse(d.path, depth + 1)
			end
		end

		-- Render files
		for _, f in ipairs(files) do
			local indent = string.rep("  ", depth + 1)
			local ext = vim.fn.fnamemodify(f.path, ":e"):lower()
			local is_md = (ext == "md")

			local title = nil
			local metadata = nil
			if is_md then
				metadata, _ = parser.read_file(f.path)
				if metadata then
					title = metadata.title
				end
			end

			local display_name
			if is_md then
				title = title or vim.fn.fnamemodify(f.path, ":t:r")
				display_name = title
			else
				display_name = vim.fn.fnamemodify(f.path, ":t")
			end

			local icon, icon_hl
			if is_md and metadata and metadata.icon and metadata.icon ~= "" then
				icon = metadata.icon
				if not icon:match("%s$") then
					icon = icon .. " "
				end
				icon_hl = "Special"
			else
				icon, icon_hl = get_file_icon(f.path)
			end

			local line_text = string.format("%s%s%s", indent, icon, display_name)
			table.insert(lines, line_text)
			local line_idx = #lines - 1
			line_to_path[line_idx + 1] = f.path

			-- Highlight file
			local start_col = #indent
			table.insert(
				highlight_actions,
				{ line = line_idx, hl = icon_hl, start_col = start_col, end_col = start_col + #icon }
			)
			table.insert(
				highlight_actions,
				{ line = line_idx, hl = "Normal", start_col = start_col + #icon, end_col = -1 }
			)
		end
	end

	traverse(config.notes_dir, 0)

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	local ns_id = vim.api.nvim_create_namespace("NotesExplorerHL")
	vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
	for _, hl_act in ipairs(highlight_actions) do
		vim.api.nvim_buf_add_highlight(buf, ns_id, hl_act.hl, hl_act.line, hl_act.start_col, hl_act.end_col)
	end

	_G.notes_explorer_line_to_path = line_to_path
	M.bind_explorer_keys(buf, line_to_path)

	if cursor then
		local total_lines = vim.api.nvim_buf_line_count(buf)
		if cursor[1] > total_lines then
			cursor[1] = total_lines
		end
		pcall(vim.api.nvim_win_set_cursor, cur_win, cursor)
	end
end

-- Bind explorer keymaps for navigation and commands
M.bind_explorer_keys = function(buf, line_to_path)
	local function get_relative_path(abs_path)
		local notes_dir = config.notes_dir
		if abs_path:sub(1, #notes_dir) == notes_dir then
			local rel = abs_path:sub(#notes_dir + 1)
			if rel:sub(1, 1) == "/" then
				rel = rel:sub(2)
			end
			return rel
		end
		return ""
	end

	local function get_relative_dir(abs_dir)
		local rel = get_relative_path(abs_dir)
		if rel ~= "" and rel:sub(-1) ~= "/" then
			rel = rel .. "/"
		end
		return rel
	end

	local function get_context_dir()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if note_path then
			if vim.fn.isdirectory(note_path) == 1 then
				return note_path
			else
				return vim.fn.fnamemodify(note_path, ":h")
			end
		end
		return config.notes_dir
	end

	local function open_note()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if not note_path then
			return
		end

		if vim.fn.isdirectory(note_path) == 1 then
			_G.notes_explorer_expanded[note_path] = not _G.notes_explorer_expanded[note_path]
			M.render_explorer(buf)
			return
		end

		local ext = vim.fn.fnamemodify(note_path, ":e"):lower()
		if ext ~= "md" then
			-- If snacks.image is active and supports the file/terminal, open it inside Neovim
			local has_snacks_image = false
			if _G.Snacks and _G.Snacks.image and _G.Snacks.image.supports then
				has_snacks_image = _G.Snacks.image.supports(note_path)
			end

			if has_snacks_image then
				if config.editor_style ~= "float" and config.editor_style ~= "tab" then
					vim.cmd("wincmd p")
				end
				open_note_buffer(note_path)
				return
			end

			-- Non-markdown asset (like an image), open with system viewer
			if vim.ui.open then
				vim.ui.open(note_path)
			else
				local opener = "xdg-open"
				if vim.fn.has("macunix") == 1 then
					opener = "open"
				elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
					opener = "start"
				end
				vim.fn.jobstart({ opener, note_path }, { detach = true })
			end
			vim.notify("Opening asset in system viewer...", vim.log.levels.INFO)
			return
		end

		if config.editor_style ~= "float" and config.editor_style ~= "tab" then
			vim.cmd("wincmd p")
		end
		open_note_buffer(note_path)
	end

	local function delete_note()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if not note_path then
			return
		end

		local filename = vim.fn.fnamemodify(note_path, ":t")
		local is_dir = vim.fn.isdirectory(note_path) == 1
		local type_str = "file"
		if is_dir then
			type_str = "directory"
		else
			local ext = vim.fn.fnamemodify(note_path, ":e"):lower()
			if ext == "md" then
				type_str = "note"
			elseif ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "webp" or ext == "gif" or ext == "svg" then
				type_str = "image"
			end
		end

		local confirm = vim.fn.confirm("Delete " .. type_str .. " '" .. filename .. "'?", "&Yes\n&No", 2)
		if confirm == 1 then
			vim.fn.delete(note_path, "rf")
			vim.notify(
				(is_dir and "Directory" or (type_str:sub(1, 1):upper() .. type_str:sub(2))) .. " deleted: " .. filename,
				vim.log.levels.INFO
			)
			M.render_explorer(buf)
			require("notes.git").commit("delete " .. type_str .. ": " .. filename)
		end
	end

	local function rename_note()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if not note_path then
			return
		end

		local parent_dir = vim.fn.fnamemodify(note_path, ":h")

		if vim.fn.isdirectory(note_path) == 1 then
			local dirname = vim.fn.fnamemodify(note_path, ":t")
			vim.ui.input({ prompt = "Rename directory: ", default = dirname }, function(new_name)
				if not new_name or new_name == "" or new_name == dirname then
					return
				end
				local new_path = parent_dir .. "/" .. new_name
				if vim.fn.isdirectory(new_path) == 1 or vim.fn.filereadable(new_path) == 1 then
					vim.notify("Path already exists: " .. new_name, vim.log.levels.WARN)
					return
				end
				local ok, err = os.rename(note_path, new_path)
				if ok then
					vim.notify("Directory renamed to: " .. new_name, vim.log.levels.INFO)
					M.render_explorer(buf)
					require("notes.git").commit(string.format("rename directory: %s -> %s", dirname, new_name))
				else
					vim.notify("Failed to rename directory: " .. tostring(err), vim.log.levels.ERROR)
				end
			end)
			return
		end

		local ext = vim.fn.fnamemodify(note_path, ":e"):lower()
		if ext ~= "md" then
			-- Non-markdown asset (like an image), rename directly
			local filename = vim.fn.fnamemodify(note_path, ":t")
			vim.ui.input({ prompt = "Rename file: ", default = filename }, function(new_name)
				if not new_name or new_name == "" or new_name == filename then
					return
				end
				local new_path = parent_dir .. "/" .. new_name
				if vim.fn.filereadable(new_path) == 1 then
					vim.notify("File already exists: " .. new_name, vim.log.levels.WARN)
					return
				end
				local ok, err = os.rename(note_path, new_path)
				if ok then
					vim.notify("File renamed to: " .. new_name, vim.log.levels.INFO)
					M.render_explorer(buf)
					require("notes.git").commit(string.format("rename file: %s -> %s", filename, new_name))
				else
					vim.notify("Failed to rename file: " .. tostring(err), vim.log.levels.ERROR)
				end
			end)
			return
		end

		local metadata, body = parser.read_file(note_path)
		if not metadata then
			return
		end

		vim.ui.input({ prompt = "Rename note title: ", default = metadata.title }, function(new_title)
			if not new_title or new_title == "" then
				return
			end
			local sanitized = utils.sanitize_title(new_title)
			local date = metadata.date:sub(1, 10)
			local parent_dir = vim.fn.fnamemodify(note_path, ":h")
			local new_filename
			if parent_dir == config.notes_dir then
				new_filename = string.format("%s_%s.md", sanitized, date)
			else
				new_filename = sanitized .. ".md"
			end
			local new_path = parent_dir .. "/" .. new_filename

			metadata.title = new_title
			local new_content = parser.format_frontmatter(metadata) .. "\n" .. body

			local file = io.open(new_path, "w")
			if file then
				file:write(new_content)
				file:close()
				if new_path ~= note_path then
					os.remove(note_path)
				end
				vim.notify("Note renamed to: " .. new_filename, vim.log.levels.INFO)
				M.render_explorer(buf)
				require("notes.git").commit(
					string.format("rename note: %s -> %s", vim.fn.fnamemodify(note_path, ":t"), new_filename)
				)
			else
				vim.notify("Failed to rename note file.", vim.log.levels.ERROR)
			end
		end)
	end

	local function add_item()
		local context_dir = get_context_dir()
		local rel_dir = get_relative_dir(context_dir)

		vim.ui.input({
			prompt = "New file/dir path (ends with / for dir): ",
			default = rel_dir,
		}, function(input_path)
			if not input_path or input_path == "" or input_path == rel_dir then
				return
			end

			local is_dir = input_path:sub(-1) == "/"
			local abs_path = config.notes_dir .. "/" .. input_path

			if is_dir then
				-- Remove trailing slash for directory creation logic
				local clean_path = abs_path:gsub("/+$", "")
				local clean_rel = input_path:gsub("/+$", "")
				if vim.fn.isdirectory(clean_path) == 1 then
					vim.notify("Directory already exists: " .. clean_rel, vim.log.levels.WARN)
					return
				end
				vim.fn.mkdir(clean_path, "p")
				vim.notify("Directory created: " .. clean_rel, vim.log.levels.INFO)
				M.render_explorer(buf)
				require("notes.git").commit("create directory: " .. clean_rel)
			else
				-- It's a file
				if not input_path:match("%.md$") then
					input_path = input_path .. ".md"
					abs_path = abs_path .. ".md"
				end
				if vim.fn.filereadable(abs_path) == 1 then
					vim.notify("File already exists: " .. input_path, vim.log.levels.WARN)
					return
				end
				local parent_dir = vim.fn.fnamemodify(abs_path, ":h")
				if vim.fn.isdirectory(parent_dir) == 0 then
					vim.fn.mkdir(parent_dir, "p")
				end
				local title = vim.fn.fnamemodify(abs_path, ":t:r")
				local date = os.date("%Y-%m-%d")
				local content = config.template
				if config.templates and config.templates.default then
					content = config.templates.default
				end
				content = content:gsub("%%TITLE%%", title):gsub("%%DATE%%", date):gsub("%%BODY%%", "")
				local f = io.open(abs_path, "w")
				if f then
					f:write(content)
					f:close()
					vim.notify("Note created: " .. input_path, vim.log.levels.INFO)
					if config.editor_style ~= "float" and config.editor_style ~= "tab" then
						vim.cmd("wincmd p")
					end
					open_note_buffer(abs_path)
					M.render_explorer(buf)
					require("notes.git").commit("create note: " .. input_path)
				else
					vim.notify("Failed to create file: " .. abs_path, vim.log.levels.ERROR)
				end
			end
		end)
	end

	local function move_item()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if not note_path then
			vim.notify("Please select a file or directory to move.", vim.log.levels.WARN)
			return
		end

		local relative_path = get_relative_path(note_path)
		local is_dir = vim.fn.isdirectory(note_path) == 1
		vim.ui.input({ prompt = "Move/Rename to: ", default = relative_path }, function(input_path)
			if not input_path or input_path == "" or input_path == relative_path then
				return
			end
			if not is_dir and not input_path:match("%.md$") then
				input_path = input_path .. ".md"
			end
			local new_path = config.notes_dir .. "/" .. input_path
			if is_dir then
				if vim.fn.isdirectory(new_path) == 1 then
					vim.notify("Destination directory already exists: " .. input_path, vim.log.levels.WARN)
					return
				end
			else
				if vim.fn.filereadable(new_path) == 1 then
					vim.notify("Destination file already exists: " .. input_path, vim.log.levels.WARN)
					return
				end
			end

			local parent_dir = vim.fn.fnamemodify(new_path, ":h")
			if vim.fn.isdirectory(parent_dir) == 0 then
				vim.fn.mkdir(parent_dir, "p")
			end

			local ok = vim.fn.rename(note_path, new_path)
			if ok == 0 then
				vim.notify((is_dir and "Directory" or "Note") .. " moved to: " .. input_path, vim.log.levels.INFO)

				if not is_dir then
					local bufs = vim.api.nvim_list_bufs()
					for _, b in ipairs(bufs) do
						if vim.api.nvim_buf_is_loaded(b) then
							local name = vim.api.nvim_buf_get_name(b)
							if name ~= "" and vim.fn.resolve(name) == vim.fn.resolve(note_path) then
								vim.api.nvim_buf_set_name(b, new_path)
								vim.api.nvim_buf_call(b, function()
									vim.cmd("edit!")
								end)
							end
						end
					end
				end
				M.render_explorer(buf)
				require("notes.git").commit(string.format("move: %s -> %s", relative_path, input_path))
			else
				vim.notify("Failed to move: " .. note_path, vim.log.levels.ERROR)
			end
		end)
	end

	local function copy_item()
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local note_path = line_to_path[line_num]
		if not note_path then
			vim.notify("Please select a file or directory to copy.", vim.log.levels.WARN)
			return
		end
		copied_note_path = note_path
		local filename = vim.fn.fnamemodify(note_path, ":t")
		local is_dir = vim.fn.isdirectory(note_path) == 1
		vim.notify("Copied " .. (is_dir and "directory" or "note") .. ": " .. filename, vim.log.levels.INFO)
	end

	local function copy_dir_recursive(src, dest)
		vim.fn.mkdir(dest, "p")
		local entries = vim.fn.readdir(src)
		for _, entry in ipairs(entries) do
			local s = src .. "/" .. entry
			local d = dest .. "/" .. entry
			if vim.fn.isdirectory(s) == 1 then
				copy_dir_recursive(s, d)
			else
				local infile = io.open(s, "rb")
				if infile then
					local content = infile:read("*all")
					infile:close()
					local outfile = io.open(d, "wb")
					if outfile then
						outfile:write(content)
						outfile:close()
					end
				end
			end
		end
	end

	local function paste_item()
		if
			not copied_note_path
			or (vim.fn.filereadable(copied_note_path) == 0 and vim.fn.isdirectory(copied_note_path) == 0)
		then
			vim.notify("No copied file or directory in clipboard register.", vim.log.levels.WARN)
			return
		end

		local context_dir = get_context_dir()
		local filename = vim.fn.fnamemodify(copied_note_path, ":t")
		local target_rel = get_relative_path(context_dir .. "/" .. filename)
		local is_dir = vim.fn.isdirectory(copied_note_path) == 1

		vim.ui.input({ prompt = "Paste to: ", default = target_rel }, function(input_path)
			if not input_path or input_path == "" then
				return
			end
			if not is_dir and not input_path:match("%.md$") then
				input_path = input_path .. ".md"
			end
			local new_path = config.notes_dir .. "/" .. input_path
			if is_dir then
				if vim.fn.isdirectory(new_path) == 1 then
					vim.notify("Destination directory already exists: " .. input_path, vim.log.levels.WARN)
					return
				end
				copy_dir_recursive(copied_note_path, new_path)
				vim.notify("Directory pasted to: " .. input_path, vim.log.levels.INFO)
				M.render_explorer(buf)
				require("notes.git").commit("paste directory: " .. input_path)
			else
				if vim.fn.filereadable(new_path) == 1 then
					vim.notify("Destination file already exists: " .. input_path, vim.log.levels.WARN)
					return
				end
				local parent_dir = vim.fn.fnamemodify(new_path, ":h")
				if vim.fn.isdirectory(parent_dir) == 0 then
					vim.fn.mkdir(parent_dir, "p")
				end
				local infile = io.open(copied_note_path, "r")
				if infile then
					local content = infile:read("*all")
					infile:close()
					local outfile = io.open(new_path, "w")
					if outfile then
						outfile:write(content)
						outfile:close()
						vim.notify("Note pasted to: " .. input_path, vim.log.levels.INFO)
						M.render_explorer(buf)
						require("notes.git").commit("paste note: " .. input_path)
					else
						vim.notify("Failed to write pasted note file.", vim.log.levels.ERROR)
					end
				else
					vim.notify("Failed to read source note file.", vim.log.levels.ERROR)
				end
			end
		end)
	end
	local function show_help()
		local help_lines = {
			" Notes Explorer Keymaps",
			" =====================",
			"",
			" <CR> / o : Open note / Toggle directory",
			" a        : Add new file/dir (ends with / for dir)",
			" d        : Delete selected note/dir",
			" r        : Rename selected note/dir",
			" m        : Move selected note/dir to a new path",
			" c        : Copy selected note/dir to clipboard",
			" p        : Paste copied note/dir to folder",
			" s        : Search all notes",
			" R        : Refresh explorer",
			" q        : Close explorer sidebar",
			" ?        : Show this help menu",
			"",
			" Press 'q' or '<Esc>' to close this help window.",
		}

		local width = 60
		local height = #help_lines
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		local help_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)

		local help_win = vim.api.nvim_open_win(help_buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = " Help Menu ",
			title_pos = "center",
		})

		vim.api.nvim_set_option_value("modifiable", false, { buf = help_buf })
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = help_buf })

		local function close_help()
			if vim.api.nvim_win_is_valid(help_win) then
				vim.api.nvim_win_close(help_win, true)
			end
		end

		local help_opts = { buffer = help_buf, silent = true, noremap = true }
		vim.keymap.set("n", "q", close_help, help_opts)
		vim.keymap.set("n", "<Esc>", close_help, help_opts)
	end

	local opts = { buffer = buf, silent = true, noremap = true }
	vim.keymap.set("n", "<CR>", open_note, opts)
	vim.keymap.set("n", "o", open_note, opts)
	vim.keymap.set("n", "d", delete_note, opts)
	vim.keymap.set("n", "r", rename_note, opts)
	vim.keymap.set("n", "n", function()
		M.new_note()
	end, opts)
	vim.keymap.set("n", "q", ":close<CR>", opts)
	vim.keymap.set("n", "s", function()
		M.search_notes()
	end, opts)
	vim.keymap.set("n", "R", function()
		M.render_explorer(buf)
		vim.notify("Notes Explorer refreshed", vim.log.levels.INFO)
	end, opts)
	vim.keymap.set("n", "a", add_item, opts)
	vim.keymap.set("n", "m", move_item, opts)
	vim.keymap.set("n", "c", copy_item, opts)
	vim.keymap.set("n", "p", paste_item, opts)
	vim.keymap.set("n", "?", show_help, opts)
end

-- Toggle the dedicated explorer window
M.toggle_explorer = function()
	local explorer_win = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		if name:match(EXPLORER_BUF_NAME) then
			explorer_win = win
			break
		end
	end

	if explorer_win then
		vim.api.nvim_win_close(explorer_win, true)
		return
	end

	vim.cmd("vsplit")
	vim.cmd("wincmd H")
	vim.cmd("vertical resize 38")

	local explorer_buf = nil
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if name:match(EXPLORER_BUF_NAME) then
			explorer_buf = buf
			break
		end
	end

	if not explorer_buf then
		explorer_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(explorer_buf, EXPLORER_BUF_NAME)
	end

	vim.api.nvim_win_set_buf(0, explorer_buf)

	vim.api.nvim_set_option_value("buftype", "nofile", { buf = explorer_buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = explorer_buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = explorer_buf })
	vim.api.nvim_set_option_value("filetype", "notesexplorer", { buf = explorer_buf })
	vim.api.nvim_set_option_value("wrap", false, { win = 0 })
	vim.api.nvim_set_option_value("number", false, { win = 0 })
	vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = 0 })

	M.render_explorer(explorer_buf)

	local group = vim.api.nvim_create_augroup("NotesExplorerRefresh", { clear = true })
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		buffer = explorer_buf,
		callback = function()
			M.render_explorer(explorer_buf)
		end,
	})
end

-- API to migrate existing flat notes to date-based subdirectories
M.migrate_notes = function()
	-- Only match files directly at the root notes_dir (flat structure)
	local notes = vim.fn.globpath(config.notes_dir, "*.md", false, true)
	if #notes == 0 then
		vim.notify("No flat notes found to migrate in " .. config.notes_dir, vim.log.levels.INFO)
		return
	end

	local migrated_count = 0
	local failed_count = 0

	for _, note_path in ipairs(notes) do
		-- Skip directories if any match
		if vim.fn.isdirectory(note_path) == 0 then
			local filename = vim.fn.fnamemodify(note_path, ":t")
			local metadata, body = parser.read_file(note_path)

			local date_str = nil
			local clean_name = nil
			local is_daily = false

			-- Try to parse from filename first
			-- Case 1: daily_YYYY-MM-DD.md
			local daily_match = filename:match("^daily_(%d%d%d%d%-%d%d%-%d%d)%.md$")
			if daily_match then
				date_str = daily_match
				is_daily = true
			end

			-- Case 2: YYYY-MM-DD.md (daily note)
			if not date_str then
				local ymd_match = filename:match("^(%d%d%d%d%-%d%d%-%d%d)%.md$")
				if ymd_match then
					date_str = ymd_match
					is_daily = true
				end
			end

			-- Case 3: title_YYYY-MM-DD.md
			if not date_str then
				local title, ymd = filename:match("^(.+)_(%d%d%d%d%-%d%d%-%d%d)%.md$")
				if title and ymd then
					clean_name = title
					date_str = ymd
				end
			end

			-- Case 4: Any other file, fallback to metadata or file mtime
			if not date_str then
				if metadata and metadata.date and metadata.date ~= "" then
					date_str = metadata.date:sub(1, 10)
				else
					local mtime = vim.fn.getftime(note_path)
					date_str = os.date("%Y-%m-%d", mtime)
				end
				clean_name = vim.fn.fnamemodify(filename, ":r")
			end

			-- Parse YYYY, MM, DD
			local yyyy, mm, dd
			if date_str then
				yyyy, mm, dd = date_str:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
			end
			if not yyyy or not mm or not dd then
				yyyy, mm, dd = "1970", "01", "01"
			end

			local target_dir = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
			if vim.fn.isdirectory(target_dir) == 0 then
				vim.fn.mkdir(target_dir, "p")
			end

			local target_filename
			if is_daily then
				target_filename = "daily.md"
			else
				target_filename = clean_name .. ".md"
			end

			local target_path = target_dir .. "/" .. target_filename

			-- Handle name collision
			local counter = 1
			local base_clean_name = target_filename:sub(1, -4)
			while vim.fn.filereadable(target_path) == 1 do
				target_filename = string.format("%s_%03d.md", base_clean_name, counter)
				target_path = target_dir .. "/" .. target_filename
				counter = counter + 1
			end

			-- Move file
			local ok, err = os.rename(note_path, target_path)
			if not ok then
				-- Fallback: copy & delete
				local infile = io.open(note_path, "rb")
				if infile then
					local outfile = io.open(target_path, "wb")
					if outfile then
						outfile:write(infile:read("*all"))
						outfile:close()
						infile:close()
						os.remove(note_path)
						ok = true
					else
						infile:close()
					end
				end
			end

			if ok then
				migrated_count = migrated_count + 1
			else
				failed_count = failed_count + 1
			end
		end
	end

	local msg = string.format("Migration finished: %d notes migrated successfully.", migrated_count)
	if failed_count > 0 then
		msg = msg .. string.format(" %d failed.", failed_count)
		vim.notify(msg, vim.log.levels.ERROR)
	else
		vim.notify(msg, vim.log.levels.INFO)
	end
end

-- API to list all unique tags and display them in a Telescope picker
M.list_tags = function()
	local notes = vim.fn.globpath(config.notes_dir, "**/*.md", false, true)
	local tag_counts = {}
	local tag_notes = {}

	for _, note_path in ipairs(notes) do
		local metadata, _ = parser.read_file(note_path)
		if metadata and metadata.tags then
			local date = metadata.date or ""
			if date == "" then
				local mtime = vim.fn.getftime(note_path)
				date = os.date("%Y-%m-%d %H:%M:%S", mtime)
			end
			local note_item = {
				path = note_path,
				title = metadata.title or vim.fn.fnamemodify(note_path, ":t:r"),
				date = date,
				tags = metadata.tags,
				summary = metadata.summary or "",
			}
			for _, tag in ipairs(metadata.tags) do
				if tag ~= "" then
					tag_counts[tag] = (tag_counts[tag] or 0) + 1
					if not tag_notes[tag] then
						tag_notes[tag] = {}
					end
					table.insert(tag_notes[tag], note_item)
				end
			end
		end
	end

	local results = {}
	for tag, count in pairs(tag_counts) do
		table.insert(results, { tag = tag, count = count })
	end

	if #results == 0 then
		vim.notify("No tags found in notes.", vim.log.levels.INFO)
		return
	end

	table.sort(results, function(a, b)
		return a.tag < b.tag
	end)

	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 2 }, -- Icon
			{ width = 25 }, -- Tag Name
			{ remaining = true }, -- Count
		},
	})

	pickers
		.new({}, {
			prompt_title = "Tags List",
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					return {
						value = entry.tag,
						display = function(tbl)
							return displayer({
								{ "", "Identifier" },
								{ tbl.tag, "Normal" },
								{ string.format("(%d notes)", entry.count), "Comment" },
							})
						end,
						ordinal = entry.tag,
						tag = entry.tag,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						local selected_tag = selection.tag
						local notes_for_tag = tag_notes[selected_tag] or {}
						table.sort(notes_for_tag, function(a, b)
							return (a.date or "") > (b.date or "")
						end)
						show_notes_picker("Notes with Tag: " .. selected_tag, notes_for_tag)
					end
				end)
				return true
			end,
		})
		:find()
end

-- API to find backlinks pointing to the active note buffer
M.list_backlinks = function()
	local active_buf = vim.api.nvim_get_current_buf()
	local active_file = vim.api.nvim_buf_get_name(active_buf)
	if active_file == "" or vim.fn.filereadable(active_file) == 0 then
		vim.notify("Active buffer is not a readable file.", vim.log.levels.ERROR)
		return
	end

	local notes_abs = vim.fn.resolve(config.notes_dir)
	local active_abs = vim.fn.resolve(active_file)
	if active_abs:sub(1, #notes_abs) ~= notes_abs then
		vim.notify("Active file is not inside notes directory.", vim.log.levels.ERROR)
		return
	end

	local metadata, _ = parser.read_file(active_abs)
	local title = metadata and metadata.title or nil
	local filename = vim.fn.fnamemodify(active_abs, ":t:r")

	local patterns = {}
	if title and title ~= "" then
		table.insert(patterns, "%[%[" .. vim.pesc(title) .. "%]%]")
	end
	table.insert(patterns, "%[%[" .. vim.pesc(filename) .. "%]%]")

	local rel_path = active_abs:sub(#notes_abs + 2)
	local rel_path_no_ext = rel_path:sub(1, -4)
	table.insert(patterns, "%[%[" .. vim.pesc(rel_path) .. "%]%]")
	table.insert(patterns, "%[%[" .. vim.pesc(rel_path_no_ext) .. "%]%]")

	local notes = vim.fn.globpath(config.notes_dir, "**/*.md", false, true)
	local results = {}

	for _, note_path in ipairs(notes) do
		if vim.fn.resolve(note_path) ~= active_abs then
			local content_file = io.open(note_path, "r")
			if content_file then
				local content = content_file:read("*all")
				content_file:close()

				local has_link = false
				for _, pattern in ipairs(patterns) do
					if content:find(pattern) then
						has_link = true
						break
					end
				end

				if has_link then
					local note_meta, _ = parser.read_file(note_path)
					local date = note_meta and note_meta.date or ""
					if date == "" then
						local mtime = vim.fn.getftime(note_path)
						date = os.date("%Y-%m-%d %H:%M:%S", mtime)
					end
					table.insert(results, {
						path = note_path,
						title = note_meta and note_meta.title or vim.fn.fnamemodify(note_path, ":t:r"),
						date = date,
						tags = note_meta and note_meta.tags or {},
						summary = note_meta and note_meta.summary or "",
					})
				end
			end
		end
	end

	if #results == 0 then
		vim.notify("No backlinks found for this note.", vim.log.levels.INFO)
		return
	end

	table.sort(results, function(a, b)
		return (a.date or "") > (b.date or "")
	end)

	show_notes_picker("Backlinks to: " .. (title or filename), results)
end

-- API to rename the note in the active buffer
M.rename_active_note = function()
	local active_buf = vim.api.nvim_get_current_buf()
	local active_file = vim.api.nvim_buf_get_name(active_buf)
	if active_file == "" or vim.fn.filereadable(active_file) == 0 then
		vim.notify("Active buffer is not a readable file.", vim.log.levels.ERROR)
		return
	end

	local notes_abs = vim.fn.resolve(config.notes_dir)
	local active_abs = vim.fn.resolve(active_file)
	if active_abs:sub(1, #notes_abs) ~= notes_abs then
		vim.notify("Active file is not inside notes directory.", vim.log.levels.ERROR)
		return
	end

	local current_dir = vim.fn.fnamemodify(active_abs, ":h")
	local old_filename = vim.fn.fnamemodify(active_abs, ":t")

	prompt_title_popup(function(new_title)
		if not new_title or new_title == "" then
			return
		end

		local sanitized = utils.sanitize_title(new_title)
		local target_path = current_dir .. "/" .. sanitized .. ".md"

		if target_path == active_abs then
			local metadata, body = parser.read_file(active_abs)
			if metadata then
				metadata.title = new_title
				local formatted = parser.format_frontmatter(metadata) .. "\n" .. body
				local f = io.open(active_abs, "w")
				if f then
					f:write(formatted)
					f:close()
					vim.cmd("edit")
					vim.notify("Note title updated.", vim.log.levels.INFO)
					require("notes.git").commit("rename note title: " .. new_title)
				end
			end
			return
		end

		if vim.fn.filereadable(target_path) == 1 then
			vim.notify("A file with that name already exists.", vim.log.levels.ERROR)
			return
		end

		if vim.bo[active_buf].modified then
			vim.cmd("write")
		end

		local ok, err = os.rename(active_abs, target_path)
		if not ok then
			vim.notify("Failed to rename file: " .. tostring(err), vim.log.levels.ERROR)
			return
		end

		local metadata, body = parser.read_file(target_path)
		if metadata then
			metadata.title = new_title
			local formatted = parser.format_frontmatter(metadata) .. "\n" .. body
			local f = io.open(target_path, "w")
			if f then
				f:write(formatted)
				f:close()
			end
		end

		vim.cmd("edit " .. vim.fn.fnameescape(target_path))
		pcall(vim.api.nvim_buf_delete, active_buf, { force = true })
		vim.notify("Note renamed to: " .. sanitized .. ".md", vim.log.levels.INFO)
		require("notes.git").commit(string.format("rename note: %s -> %s", old_filename, sanitized .. ".md"))
	end)
end

-- API to delete the note in the active buffer
M.delete_active_note = function()
	local active_buf = vim.api.nvim_get_current_buf()
	local active_file = vim.api.nvim_buf_get_name(active_buf)
	if active_file == "" or vim.fn.filereadable(active_file) == 0 then
		vim.notify("Active buffer is not a readable file.", vim.log.levels.ERROR)
		return
	end

	local notes_abs = vim.fn.resolve(config.notes_dir)
	local active_abs = vim.fn.resolve(active_file)
	if active_abs:sub(1, #notes_abs) ~= notes_abs then
		vim.notify("Active file is not inside notes directory.", vim.log.levels.ERROR)
		return
	end

	local filename = vim.fn.fnamemodify(active_abs, ":t")
	local confirm = vim.fn.confirm("Delete note '" .. filename .. "'?", "&Yes\n&No", 2)
	if confirm == 1 then
		os.remove(active_abs)
		pcall(vim.api.nvim_buf_delete, active_buf, { force = true })
		vim.notify("Note deleted: " .. filename, vim.log.levels.INFO)
		require("notes.git").commit("delete note: " .. filename)
	end
end

-- API to quickly capture a note/task and append it to today's daily note
M.quick_capture = function()
	local width = 60
	local height = 4
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Quick Capture (Scratchpad) ",
		title_pos = "center",
		footer = " <C-s> or <CR>: save & close | q: cancel ",
		footer_pos = "center",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
	vim.cmd("startinsert")

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		local mode = vim.api.nvim_get_mode().mode
		if mode:sub(1, 1) == "i" then
			vim.cmd("stopinsert")
		end
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		-- Filter out empty lines and ensure list item formatting
		local cleaned_lines = {}
		for _, l in ipairs(lines) do
			local trimmed = vim.trim(l)
			if trimmed ~= "" then
				if not trimmed:match("^%s*[-*+]") then
					trimmed = "- [ ] " .. trimmed
				end
				table.insert(cleaned_lines, trimmed)
			end
		end

		close()

		if #cleaned_lines > 0 then
			local date = os.date(config.date_format)
			local yyyy, mm, dd = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
			local dir_path = config.notes_dir
			local filename
			if yyyy and mm and dd then
				dir_path = string.format("%s/%s/%s/%s", config.notes_dir, yyyy, mm, dd)
				filename = "daily.md"
			else
				filename = "daily_" .. date .. ".md"
			end
			local full_path = dir_path .. "/" .. filename

			-- If the daily note doesn't exist, create it
			if vim.fn.filereadable(full_path) == 0 then
				local legacy_path = config.notes_dir .. "/" .. date .. ".md"
				if vim.fn.filereadable(legacy_path) == 1 then
					full_path = legacy_path
				else
					create_daily_note_at_path(full_path, dir_path, date)
				end
			end

			-- Read daily note lines to locate target section
			local file_lines = {}
			local r_file = io.open(full_path, "r")
			if r_file then
				for line in r_file:lines() do
					table.insert(file_lines, line)
				end
				r_file:close()
			end

			local heading_idx = nil
			-- Search patterns: "## Tasks / Notes", "## Tasks", "## Notes" (case-insensitive)
			local patterns = {
				"^##+%s+.*[Tt]asks%s*/%s*[Nn]otes",
				"^##+%s+.*[Tt]asks",
				"^##+%s+.*[Nn]otes",
			}
			for _, pat in ipairs(patterns) do
				for i, line in ipairs(file_lines) do
					if line:match(pat) then
						heading_idx = i
						break
					end
				end
				if heading_idx then
					break
				end
			end

			local insert_idx
			if heading_idx then
				-- Find the next heading of any level
				insert_idx = #file_lines + 1
				for i = heading_idx + 1, #file_lines do
					if file_lines[i]:match("^#+%s+") then
						insert_idx = i
						break
					end
				end

				-- Trim trailing empty lines within the target section
				while insert_idx > heading_idx + 1 and vim.trim(file_lines[insert_idx - 1]) == "" do
					insert_idx = insert_idx - 1
				end
			else
				-- Fallback to the absolute end of the file
				insert_idx = #file_lines + 1
			end

			-- Insert cleaned lines
			for _, line in ipairs(cleaned_lines) do
				table.insert(file_lines, insert_idx, line)
				insert_idx = insert_idx + 1
			end

			-- Write the updated contents back to the daily note
			local w_file = io.open(full_path, "w")
			if w_file then
				for _, line in ipairs(file_lines) do
					w_file:write(line .. "\n")
				end
				w_file:close()
				vim.notify("Note captured to today's daily note.", vim.log.levels.INFO)
				require("notes.git").commit("quick capture")
			else
				vim.notify("Could not write daily note: " .. full_path, vim.log.levels.ERROR)
			end
		else
			vim.notify("Quick capture cancelled: empty text", vim.log.levels.WARN)
		end
	end

	local function cancel()
		close()
		vim.notify("Quick capture cancelled", vim.log.levels.INFO)
	end

	-- Keymaps inside the capture buffer
	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, silent = true })
	vim.keymap.set("n", "<CR>", submit, { buffer = buf, silent = true })
	vim.keymap.set("n", "q", cancel, { buffer = buf, silent = true })
	vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, silent = true })
end

-- Insert TOC markers at the cursor line and generate the TOC
M.insert_toc = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local row = cursor[1] -- 1-based line number (insert below this line)

	local markers = {
		"<!-- TOC -->",
		"<!-- /TOC -->",
	}

	vim.api.nvim_buf_set_lines(bufnr, row, row, false, markers)

	-- Populate the TOC immediately
	require("notes.toc").update_toc(bufnr)

	-- Place cursor inside the inserted TOC block
	pcall(vim.api.nvim_win_set_cursor, 0, { row + 2, 0 })
	vim.notify("Table of Contents markers inserted", vim.log.levels.INFO)
end

-- Interactive document outline picker using Telescope
M.outline = function()
	local bufnr = vim.api.nvim_get_current_buf()
	local headings = require("notes.toc").parse_headings(bufnr)
	if #headings == 0 then
		vim.notify("No headings found in the current note.", vim.log.levels.INFO)
		return
	end

	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 60 }, -- Heading text with indent
			{ remaining = true }, -- Line number/metadata
		},
	})

	local make_display = function(entry)
		local heading = entry.heading
		local indent = string.rep("  ", heading.level - 1)
		local prefix = "󰉫 "
		if heading.level == 1 then
			prefix = " "
		elseif heading.level == 2 then
			prefix = "󰉬 "
		elseif heading.level == 3 then
			prefix = "󰉭 "
		end

		local hl = "TelescopeResultsNormal"
		if heading.level == 1 then
			hl = "TelescopeResultsTitle"
		end

		return displayer({
			{ indent .. prefix .. heading.text, hl },
			{ "L" .. heading.lnum, "Comment" },
		})
	end

	pickers
		.new({}, {
			prompt_title = "Document Outline (TOC)",
			sorting_strategy = "ascending",
			layout_config = {
				prompt_position = "top",
			},
			finder = finders.new_table({
				results = headings,
				entry_maker = function(heading)
					return {
						value = heading.lnum,
						display = make_display,
						ordinal = heading.text,
						heading = heading,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Section Preview",
				define_preview = function(self, entry, status)
					local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
					if package.loaded["markview"] then
						vim.schedule(function()
							local mv = require("markview").strict_render
							mv:clear(self.state.bufnr)
							mv:render(self.state.bufnr)
							-- Scroll preview window to the selected heading line
							pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.heading.lnum, 0 })
						end)
					end
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						pcall(vim.api.nvim_win_set_cursor, 0, { selection.value, 0 })
					end
				end)
				return true
			end,
		})
		:find()
end

M.choose_icon = function()
	local active_buf = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(active_buf)
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	if ext ~= "md" then
		vim.notify("Can only choose icons for Markdown notes.", vim.log.levels.ERROR)
		return
	end

	local icons_list = {
		{ icon = "☀️", name = "Sunshine / Sun" },
		{ icon = "🌞", name = "Sun Face / Morning" },
		{ icon = "🌤️", name = "Partly Sunny / Weather" },
		{ icon = "🌙", name = "Moon / Night" },
		{ icon = "❌", name = "Cancel / Cross / Reject" },
		{ icon = "🚫", name = "Prohibited / Blocked" },
		{ icon = "🛑", name = "Stop / Cancel" },
		{ icon = "✨", name = "Sparkles / Magic / AI" },
		{ icon = "🌟", name = "Glowing Star / Highlight" },
		{ icon = "❤️", name = "Heart / Favorite" },
		{ icon = "📝", name = "Note / Document" },
		{ icon = "📓", name = "Journal / Personal" },
		{ icon = "📔", name = "Diary / Log" },
		{ icon = "📚", name = "Book / Reference" },
		{ icon = "📋", name = "Clipboard / Task list" },
		{ icon = "✅", name = "Done / Complete" },
		{ icon = "⚠️", name = "Warning / Caution" },
		{ icon = "🚨", name = "Alert / Urgent" },
		{ icon = "❓", name = "Question / Query" },
		{ icon = "🎯", name = "Target / Goal" },
		{ icon = "⭐", name = "Star / Favorite" },
		{ icon = "🧠", name = "Brain / Thoughts" },
		{ icon = "💭", name = "Thought / Reflection" },
		{ icon = "💡", name = "Idea / Brainstorm" },
		{ icon = "💬", name = "Comment / Chat" },
		{ icon = "📌", name = "Pin / Reference" },
		{ icon = "📅", name = "Calendar / Schedule" },
		{ icon = "⏰", name = "Reminder / Alarm" },
		{ icon = "⏳", name = "Wait / Defer" },
		{ icon = "🔗", name = "Link / Connection" },
		{ icon = "📥", name = "Inbox / Backlog" },
		{ icon = "📤", name = "Outbox / Export" },
		{ icon = "🔍", name = "Search / Inspect" },
		{ icon = "🔥", name = "Fire / Hot / Priority" },
		{ icon = "🚀", name = "Launch / Release" },
		{ icon = "🐛", name = "Bug / Issue" },
		{ icon = "🔒", name = "Security / Lock" },
		{ icon = "🔑", name = "Key / Access" },
		{ icon = "🚩", name = "Flag / Milestone" },
		{ icon = "🔖", name = "Bookmark" },
		{ icon = "🛠️", name = "Tool / Refactor" },
		{ icon = "🎨", name = "Design / Style" },
		{ icon = "🧪", name = "Test / Experiment" },
		{ icon = "📦", name = "Package / Dependency" },
		{ icon = "🏷️", name = "Tag / Topic" },
		-- Vehicles & Transport
		{ icon = "🚗", name = "Car / Automobile" },
		{ icon = "🏎️", name = "Racing Car / Fast" },
		{ icon = "🛵", name = "Scooter / Motorbike" },
		{ icon = "🏍️", name = "Motorcycle" },
		{ icon = "🚲", name = "Bicycle / Cycle" },
		{ icon = "🚌", name = "Bus / Transit" },
		{ icon = "🚆", name = "Train / Rail" },
		{ icon = "✈️", name = "Airplane / Travel" },
		{ icon = "🚁", name = "Helicopter" },
		{ icon = "⛵", name = "Boat / Ship" },
		{ icon = "🚀", name = "Rocket / Launch" },
		-- Standard Emojis
		{ icon = "👍", name = "Thumbs Up / Like" },
		{ icon = "👎", name = "Thumbs Down / Dislike" },
		{ icon = "🎉", name = "Party / Celebration" },
		{ icon = "⚡", name = "Lightning / Fast" },
		{ icon = "☕", name = "Coffee / Break" },
		{ icon = "🍺", name = "Beer / Chill" },
		{ icon = "🍕", name = "Pizza / Food" },
		{ icon = "📂", name = "Open Folder" },
		{ icon = "📄", name = "Page / Document" },
		{ icon = "🔓", name = "Unlocked / Open" },
		-- Nerd Font Icons
		{ icon = "󰖙", name = "Nerd: Sun" },
		{ icon = "󰅖", name = "Nerd: Close / Cancel" },
		{ icon = "󰽥", name = "Nerd: Moon" },
		{ icon = "󰋑", name = "Nerd: Heart" },
		{ icon = "󰌵", name = "Nerd: Sparkles" },
		{ icon = "󰅤", name = "Nerd: Bookmark" },
		{ icon = "", name = "Nerd: Flame" },
		{ icon = "", name = "Nerd: Bug" },
		{ icon = "󰓅", name = "Nerd: Idea" },
		{ icon = "󰃭", name = "Nerd: Calendar" },
		{ icon = "󰄬", name = "Nerd: Check" },
		{ icon = "󰅶", name = "Nerd: Shield" },
		{ icon = "󰆍", name = "Nerd: Terminal" },
		{ icon = "󰙨", name = "Nerd: Lab" },
		{ icon = "󰏗", name = "Nerd: Package" },
		{ icon = "󰓎", name = "Nerd: Star" },
		{ icon = "󰀪", name = "Nerd: Warning" },
		{ icon = "󰂚", name = "Nerd: Alert / Bell" },
		{ icon = "󰘥", name = "Nerd: Question" },
		{ icon = "󰓾", name = "Nerd: Target" },
		{ icon = "󰄽", name = "Nerd: Brain" },
		{ icon = "󰆧", name = "Nerd: Book / Journal" },
		{ icon = "󰌷", name = "Nerd: Link" },
		{ icon = "󰄉", name = "Nerd: Clock" },
		{ icon = "󰈞", name = "Nerd: Search" },
		{ icon = "󰏊", name = "Nerd: Clipboard" },
		{ icon = "󰄋", name = "Nerd: Car" },
		{ icon = "󰄌", name = "Nerd: Bike" },
		{ icon = "󰄎", name = "Nerd: Airplane" },
		{ icon = "󰄏", name = "Nerd: Rocket" },
		-- Special actions
		{ icon = "", name = "[None / Clear Icon]" },
		{ icon = "CUSTOM", name = "[Enter custom icon...]" },
	}

	local displayer = entry_display.create({
		separator = " | ",
		items = {
			{ width = 4 }, -- Icon
			{ width = 30 }, -- Name
		},
	})

	local function make_display(entry)
		local icon_str = entry.value.icon
		if icon_str == "CUSTOM" then
			icon_str = "⌨️"
		elseif icon_str == "" then
			icon_str = "∅"
		end
		local formatted = displayer({
			icon_str,
			entry.value.name,
		})
		return "| " .. formatted .. " |"
	end

	local function insert_icon(icon)
		if icon ~= "" then
			vim.api.nvim_put({ icon }, "c", true, true)
		end
	end

	pickers
		.new({}, {
			prompt_title = "Choose Note Icon",
			finder = finders.new_table({
				results = icons_list,
				entry_maker = function(item)
					return {
						value = item,
						display = make_display,
						ordinal = item.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						local item = selection.value
						if item.icon == "CUSTOM" then
							vim.ui.input({ prompt = "Enter custom icon (emoji or character): " }, function(input)
								if input and input ~= "" then
									insert_icon(input)
								end
							end)
						else
							insert_icon(item.icon)
						end
					end
				end)
				return true
			end,
		})
		:find()
end

return M
