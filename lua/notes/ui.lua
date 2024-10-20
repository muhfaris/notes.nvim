local M = {}
local config = require("notes.config").config
local utils = require("notes.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

M.new_note = function()
	-- Get the full screen dimensions
	local width = vim.o.columns
	local height = vim.o.lines

	-- Create a full-screen buffer for the dimming effect
	local dim_buf = vim.api.nvim_create_buf(false, true)

	-- Fill the buffer with spaces
	local lines = {}
	for _ = 1, height do
		table.insert(lines, string.rep(" ", width))
	end
	vim.api.nvim_buf_set_lines(dim_buf, 0, -1, false, lines)

	-- Create a dimming highlight group
	vim.api.nvim_command("highlight DimBackground guibg=#000000 guifg=#000000 gui=none")

	-- Apply the highlight to the entire buffer
	vim.api.nvim_buf_add_highlight(dim_buf, -1, "DimBackground", 0, 0, -1)

	-- Display the dimming buffer in a floating window
	local dim_win = vim.api.nvim_open_win(dim_buf, false, {
		relative = "editor",
		width = width,
		height = height,
		row = 0,
		col = 0,
		style = "minimal",
	})

	-- Set window options
	vim.wo[dim_win].winblend = 30

	-- Create a centered floating window for input
	local input_buf = vim.api.nvim_create_buf(false, true)
	local input_width = 40
	local input_height = 1
	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "editor",
		width = input_width,
		height = input_height,
		row = math.floor((height - input_height) / 2),
		col = math.floor((width - input_width) / 2),
		style = "minimal",
		border = "rounded",
	})

	-- Set up the prompt
	vim.api.nvim_set_option_value("winhl", "Normal:Normal", { win = input_win })
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "Enter title note:" })

	-- Set up autocommand to close windows on BufLeave
	local group = vim.api.nvim_create_augroup("CloseInputWindow", { clear = true })
	vim.api.nvim_create_autocmd("BufLeave", {
		group = group,
		buffer = input_buf,
		callback = function()
			vim.api.nvim_win_close(input_win, true)
			vim.api.nvim_win_close(dim_win, true)
		end,
	})

	-- Start insert mode at the end of the prompt
	vim.cmd("startinsert!")
	vim.cmd("normal! $")

	vim.ui.input({ prompt = "Enter title note:" }, function(input)
		-- Check if windows still exist before closing them
		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		if vim.api.nvim_win_is_valid(dim_win) then
			vim.api.nvim_win_close(dim_win, true)
		end

		-- Continue with the rest of your new_note function
		if input and input ~= "" then
			-- Your existing code for creating a new note
			local title = input
			local date = os.date(config.date_format)
			local time = os.date(config.time_format)
			local sanitized_title = utils.sanitize_title(title)
			local filename = string.format("%s_%s.md", sanitized_title, date)
			local full_path = config.notes_dir .. "/" .. filename
			vim.cmd("edit " .. full_path)
			local template = config.template
			template = template:gsub("%%TITLE%%", title)
			template = template:gsub("%%DATE%%", date .. " " .. time)
			template = template:gsub("%%LABEL%%", "")
			template = template:gsub("%%BODY%%", "")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "\n"))
			local intro_line = vim.fn.search("^## Introduction")
			if intro_line > 0 then
				vim.api.nvim_win_set_cursor(0, { intro_line + 1, 0 })
			end
			vim.cmd("startinsert")
		else
			print("Note creation cancelled.")
		end
	end)
end

M.list_notes = function()
	local notes = vim.fn.globpath(config.notes_dir, "*.md", false, 1)
	local notes_by_date = {}

	local function get_note_info(file_path)
		local file = io.open(file_path, "r")
		local title, summary

		if file then
			local content = file:read("*all")
			file:close()

			title = content:match("^# Title:%s*(.-)\n")
			summary = content:match("## Summary\n(.-)\n##")

			return title or vim.fn.fnamemodify(file_path, ":t:r"), summary or "No summary"
		end
	end

	local function delete_note(prompt_bufnr)
		local selection = action_state.get_selected_entry()
		if selection.type ~= "Note" then
			print("Cannot delete: not a note")
			return
		end

		local note_path = selection.value
		local filename = vim.fn.fnamemodify(note_path, ":t")
		local confirm = vim.fn.input("Delete note '" .. filename .. "'? (y/N): ")
		if confirm:lower() ~= "y" then
			print("Deletion cancelled.")
			return
		end

		local success, err = os.remove(note_path)
		if success then
			print("Note '" .. filename .. "' deleted successfully.")
			actions.close(prompt_bufnr)
			M.list_notes_telescope() -- Refresh the list
		else
			print("Error deleting note: " .. (err or "Unknown error"))
		end
	end

	for _, note in ipairs(notes) do
		local date = vim.fn.fnamemodify(note, ":t"):match("_(%d+%-%d+%-%d+)")
		if date then
			if not notes_by_date[date] then
				notes_by_date[date] = {}
			end
			local title, summary = get_note_info(note)
			table.insert(notes_by_date[date], { path = note, title = title, summary = summary })
		end
	end

	local flatten_notes = {}
	for date, date_notes in pairs(notes_by_date) do
		table.insert(flatten_notes, { date, "Date", "", "" })
		for _, note in ipairs(date_notes) do
			table.insert(flatten_notes, { note.path, "Note", note.title, note.summary })
		end
	end

	pickers
		.new({}, {
			prompt_title = "Notes",
			finder = finders.new_table({
				results = flatten_notes,
				entry_maker = function(entry)
					return {
						value = entry[1],
						display = function(entry)
							if entry.type == "Date" then
								return entry.value
							else
								-- local display_title = string.format("%-30s", entry.ordinal:sub(1, 30))
								-- local display_title = string.format("%s", entry.ordinal)
								local display_title = entry.title
								local display_summary = entry.summary
								return string.format(" %s  %s", display_title, display_summary or "No summary")
							end
						end,
						ordinal = entry[3] .. " " .. entry[1],
						type = entry[2],
						title = entry[3],
						summary = entry[4],
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection.type == "Note" then
						vim.cmd("edit " .. selection.value)
					end
				end)

				-- Add delete mapping
				map("i", "<C-d>", function()
					delete_note(prompt_bufnr)
				end)
				map("n", "d", function()
					delete_note(prompt_bufnr)
				end)

				return true
			end,
		})
		:find()
end

return M
