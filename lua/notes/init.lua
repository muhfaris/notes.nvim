-- ~/.config/nvim/lua/notes/init.lua

local api = vim.api
local fn = vim.fn

local M = {}

-- Default configuration
M.config = {
	notes_dir = fn.expand("~/.notes"),
	date_format = "%Y-%m-%d",
	time_format = "%H:%M:%S",
	template = [[
# Title: %TITLE%

## Date: %DATE%

## Labels: %LABEL%

## Summary

## Description

%BODY%

## Conclusion
]],
}

-- Function to set up the plugin
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Ensure the notes directory exists
	if fn.isdirectory(M.config.notes_dir) == 0 then
		fn.mkdir(M.config.notes_dir, "p")
	end
end

-- Function to sanitize the title for use in filename
local function sanitize_title(title)
	-- Replace spaces and non-alphanumeric characters with hyphens
	local sanitized = title:gsub("[^%w%s-]", ""):gsub("%s+", "-"):lower()
	-- Trim hyphens from start and end
	return sanitized:gsub("^-+", ""):gsub("-+$", "")
end

function M.new_note()
	-- Get the full screen dimensions
	local width = vim.o.columns
	local height = vim.o.lines

	-- Create a full-screen buffer for the dimming effect
	local dim_buf = api.nvim_create_buf(false, true)

	-- Fill the buffer with spaces
	local lines = {}
	for _ = 1, height do
		table.insert(lines, string.rep(" ", width))
	end
	api.nvim_buf_set_lines(dim_buf, 0, -1, false, lines)

	-- Create a dimming highlight group
	api.nvim_command("highlight DimBackground guibg=#000000 guifg=#000000 gui=none")

	-- Apply the highlight to the entire buffer
	api.nvim_buf_add_highlight(dim_buf, -1, "DimBackground", 0, 0, -1)

	-- Display the dimming buffer in a floating window
	local dim_win = api.nvim_open_win(dim_buf, false, {
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
	local input_buf = api.nvim_create_buf(false, true)
	local input_width = 40
	local input_height = 1
	local input_win = api.nvim_open_win(input_buf, true, {
		relative = "editor",
		width = input_width,
		height = input_height,
		row = math.floor((height - input_height) / 2),
		col = math.floor((width - input_width) / 2),
		style = "minimal",
		border = "rounded",
	})

	-- Set up the prompt
	api.nvim_buf_set_lines(input_buf, 0, -1, false, { "Enter title note:" })
	api.nvim_set_option_value("winhl", "Normal:Normal", { win = input_win })

	-- Set up autocommand to close windows on BufLeave
	local group = api.nvim_create_augroup("CloseInputWindow", { clear = true })
	api.nvim_create_autocmd("BufLeave", {
		group = group,
		buffer = input_buf,
		callback = function()
			api.nvim_win_close(input_win, true)
			api.nvim_win_close(dim_win, true)
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
			local date = os.date(M.config.date_format)
			local time = os.date(M.config.time_format)
			local sanitized_title = sanitize_title(title)
			local filename = string.format("%s_%s.md", sanitized_title, date)
			local full_path = M.config.notes_dir .. "/" .. filename
			vim.cmd("edit " .. full_path)
			local template = M.config.template
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

	-- Prompt for the note title
	-- vim.ui.input({ prompt = "Enter title note: " }, function(input)
	-- 	-- Close the dimming window
	-- 	api.nvim_win_close(dim_win, true)
	--
	-- 	-- Continue with the rest of your new_note function
	-- 	if input and input ~= "" then
	-- 		-- Your existing code for creating a new note
	-- 		local title = input
	-- 		local date = os.date(M.config.date_format)
	-- 		local time = os.date(M.config.time_format)
	-- 		local sanitized_title = sanitize_title(title)
	-- 		local filename = string.format("%s_%s.md", sanitized_title, date)
	-- 		local full_path = M.config.notes_dir .. "/" .. filename
	--
	-- 		vim.cmd("edit " .. full_path)
	--
	-- 		local template = M.config.template
	-- 		template = template:gsub("%%TITLE%%", title)
	-- 		template = template:gsub("%%DATE%%", date .. " " .. time)
	-- 		template = template:gsub("%%LABEL%%", "")
	-- 		template = template:gsub("%%BODY%%", "")
	--
	-- 		vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "\n"))
	--
	-- 		local intro_line = vim.fn.search("^## Introduction")
	-- 		if intro_line > 0 then
	-- 			vim.api.nvim_win_set_cursor(0, { intro_line + 1, 0 })
	-- 		end
	-- 		vim.cmd("startinsert")
	-- 	else
	-- 		print("Note creation cancelled.")
	-- 	end
	-- end)
end

-- Add this new function to delete a note
local function delete_note(filename)
	local full_path = fn.fnamemodify(M.config.notes_dir .. "/" .. filename, ":p")

	-- Confirm deletion
	local confirm = vim.fn.input("Delete note '" .. full_path .. "'? (y/N): ")
	if confirm:lower() ~= "y" then
		print("Deletion cancelled.")
		return false
	end

	-- Try to delete the file
	local success, err = os.remove(full_path)
	if success then
		print("Note '" .. filename .. "' deleted successfully.")
		return true
	else
		print("Error deleting note: " .. (err or "Unknown error"))
		return false
	end
end

function M.list_notes()
	local notes = fn.globpath(M.config.notes_dir, "*.md", 0, 1)
	if #notes == 0 then
		print("No notes found.")
		return
	end

	-- Create a table to store notes grouped by date
	local notes_by_date = {}

	-- Iterate over each note and categorize by the date extracted from the filename
	for _, note in ipairs(notes) do
		-- Extract the date from the filename
		local date = fn.fnamemodify(note, ":t"):match("_(%d+%-%d+%-%d+)")

		if date then
			if not notes_by_date[date] then
				notes_by_date[date] = {}
			end
			table.insert(notes_by_date[date], note)
		end
	end

	-- Prepare the buffer for display
	-- Check if "Notes List" buffer already exists
	local existing_buf = vim.fn.bufnr("Notes List")
	local buf
	if existing_buf ~= -1 and vim.fn.bufexists(existing_buf) == 1 then
		-- Use the existing buffer
		buf = existing_buf
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	else
		-- Create a new buffer
		vim.cmd("vnew")
		buf = api.nvim_get_current_buf()
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		api.nvim_buf_set_name(buf, "Notes List")
	end

	-- Create lines for each date and associated notes
	local lines = { "📚 Notes:", "" }
	for date, notes in pairs(notes_by_date) do
		table.insert(lines, " Date: " .. date)
		for _, note in ipairs(notes) do
			table.insert(lines, "")
			local note_name = fn.fnamemodify(note, ":t")
			table.insert(lines, string.format("   %s", note_name))
		end
		table.insert(lines, "") -- Add a blank line for spacing
	end

	api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.cmd("setlocal nomodifiable")

	-- Set up a click handler to open the selected note
	local function open_note()
		local cursor_line = api.nvim_get_current_line()

		-- trim all space
		cursor_line = cursor_line:gsub("%s+", "")

		-- Extract the note filename from the cursor line
		local note_filename = cursor_line:gsub("^%s*", "")
		if note_filename then
			local full_path = fn.fnamemodify(M.config.notes_dir .. "/" .. note_filename, ":p")
			vim.cmd("edit " .. full_path)
		end
	end

	-- Function to refresh the notes list
	local function refresh_notes_list()
		M.list_notes()
	end

	-- Set up a handler to delete the selected note
	local function delete_current_note()
		local cursor_line = api.nvim_get_current_line()
		local note_filename = cursor_line:match("^%s*%- (.+%.md)$")
		if note_filename then
			if delete_note(note_filename) then
				-- Refresh the notes list after successful deletion
				refresh_notes_list()
			end
		else
			print("No valid note selected for deletion.")
		end
	end

	-- Set the click event to open the note when a line is clicked
	api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		noremap = true,
		silent = true,
		callback = open_note,
	})

	-- Set the 'd' key to delete the current note
	api.nvim_buf_set_keymap(buf, "n", "d", "", {
		noremap = true,
		silent = true,
		callback = delete_current_note,
	})
end

function M.paste_image()
	local image_dir = M.config.notes_dir .. "/images"
	if vim.fn.isdirectory(image_dir) == 0 then
		vim.fn.mkdir(image_dir, "p")
	end

	local image_path = image_dir .. "/" .. os.time() .. ".png"
	vim.fn.system("xclip -selection clipboard -t image/png -o > " .. image_path)
	vim.cmd("normal! i![](" .. image_path .. ")")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

function M.list_notes_telescope()
	local notes = vim.fn.globpath(M.config.notes_dir, "*.md", false, 1)
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

	local function split_by_pipe(input_string)
		return vim.split(input_string, "|", { trimempty = true })
	end

	local function delete_notex(prompt_bufnr)
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
					delete_notex(prompt_bufnr)
				end)
				map("n", "d", function()
					delete_notex(prompt_bufnr)
				end)

				return true
			end,
		})
		:find()
end

-- Set up commands
vim.cmd([[
    command! NewNote lua require('notes').new_note()
    command! ListNotes lua require('notes').list_notes_telescope()
    command! NotePasteImage lua require('notes').paste_image()
]])

return M
