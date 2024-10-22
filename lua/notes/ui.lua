local M = {}
local config = require("notes.config").get_config()
local utils = require("notes.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- Function to truncate text and add ellipsis
local function truncate(text, width)
	if #text > width then
		return text:sub(1, width - 3) .. "..."
	end
	return text
end

local function format_display(entry)
	if entry.type == "Date" then
		return string.format(" %s", entry.value)
	elseif entry.type == "Line" then
		return "∟"
	elseif entry.type == "Space" then
		return ""
	else
		local display_title = truncate(entry.title, config.length_title)
		local display_summary = truncate(entry.summary or "No Summary", config.length_summary)
		return string.format("   %-" .. config.length_title .. "s  %s", display_title, display_summary)
	end
end

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
			if vim.api.nvim_win_is_valid(input_win) then
				vim.api.nvim_win_close(input_win, true)
			end
			if vim.api.nvim_win_is_valid(dim_win) then
				vim.api.nvim_win_close(dim_win, true)
			end
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
			vim.schedule(function()
				-- Your existing code for creating a new note
				local title = input
				local date = os.date(config.date_format)
				local time = os.date(config.time_format)
				local sanitized_title = utils.sanitize_title(title)
				local filename = string.format("%s_%s.md", sanitized_title, date)
				local full_path = config.notes_dir .. "/" .. filename

				-- Prepare template
				local template = config.template
				template = template:gsub("%%TITLE%%", title)
				template = template:gsub("%%DATE%%", date .. " " .. time)
				template = template:gsub("%%LABEL%%", "")
				template = template:gsub("%%BODY%%", "")

				-- Create and write initial content to the file
				local file = io.open(vim.fn.fnameescape(full_path), "w") -- Open file in write mode
				if not file then
					print("Could not create file: " .. full_path)
					return
				end

				-- Write the template
				file:write(template)
				file:close()
				vim.cmd("edit " .. full_path)

				local intro_line = vim.fn.search("^## Description")
				if intro_line > 0 then
					pcall(vim.api.nvim_win_set_cursor, 0, { intro_line + 1, 0 })
				end
			end)
		else
			print("Note creation cancelled.")
		end
	end)
end

M.list_notes = function()
	local notes = vim.fn.globpath(config.notes_dir, "*.md", false, true)
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
			M.list_notes() -- Refresh the list
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
	local sorted_dates = {}

	-- Collect dates for sorting
	for date in pairs(notes_by_date) do
		table.insert(sorted_dates, date)
	end

	-- Sort dates in descending order
	table.sort(sorted_dates, function(a, b)
		return a > b
	end)

	-- Flatten notes by sorted dates
	for index, date in ipairs(sorted_dates) do
		if index ~= 1 then
			table.insert(flatten_notes, { "", "Space", "", "" })
		end

		table.insert(flatten_notes, { date, "Date", "", "" })
		table.insert(flatten_notes, { "", "Line", "", "" })

		for _, note in ipairs(notes_by_date[date]) do
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
							return format_display(entry)
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

-- Function to extract labels from a note
M.get_keywords = function(note_path)
	local labels = {}
	local file = io.open(note_path, "r")
	if file then
		for line in file:lines() do
			if line:match("^## Keywords: ") then
				local label_line = line:gsub("^## Keywords: ", ""):gsub("%s+", "") -- Remove leading text and spaces
				labels = vim.split(label_line, ",", { trimempty = true }) -- Split by comma
				break
			end
		end
		file:close()
	end
	return labels
end

-- Cache labels for all notes
M.cache_keywords = function(notes_dir)
	local label_cache = {}
	local notes = vim.fn.globpath(notes_dir, "*.md", false, true) -- Get all note files in the directory
	for _, note_path in ipairs(notes) do
		--debug
		local labels = M.get_keywords(note_path)
		label_cache[note_path] = labels
	end
	return label_cache
end

-- Search notes by labels using Telescope
M.find_by_keyword = function()
	local label_cache = M.cache_keywords(config.notes_dir)

	local all_labels = {}
	for _, labels in pairs(label_cache) do
		for _, label in ipairs(labels) do
			if not vim.tbl_contains(all_labels, label) then
				table.insert(all_labels, label) -- Collect unique labels
			end
		end
	end

	-- Use Telescope to fuzzy find labels
	pickers
		.new({}, {
			prompt_title = "Search Notes by Label",
			finder = finders.new_table({
				results = all_labels,
			}),
			sorter = conf.generic_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selected_label = action_state.get_selected_entry()[1]

					-- Find all notes containing the selected label
					local matching_notes = {}
					for note, labels in pairs(label_cache) do
						if vim.tbl_contains(labels, selected_label) then
							table.insert(matching_notes, note)
						end
					end

					-- Open another Telescope picker to select the note
					pickers
						.new({}, {
							prompt_title = "Select Note with Label: " .. selected_label,
							finder = finders.new_table({
								results = matching_notes,
							}),
							sorter = conf.generic_sorter(),
							attach_mappings = function(_, _)
								actions.select_default:replace(function(prompt_bufnr)
									local selection = action_state.get_selected_entry()
									actions.close(prompt_bufnr)

									-- Ensure that the selection is a note before opening
									local note_path = selection.value

									-- Open the selected note without causing the "Save changes" prompt
									vim.cmd("edit " .. vim.fn.fnameescape(note_path))

									-- Ensure the buffer is marked as unmodified right after opening
									vim.cmd("set nomodified")
								end)
								return true
							end,
						})
						:find()
				end)
				return true
			end,
		})
		:find()
end

return M
