-- lua/notes/shared/tasks.lua
--- Shared task detection across notes: scans notes for incomplete checklist
--- items, inline TODO/ASK markers, and #todo / #tech-debt tags. Used by the
--- Telescope task picker (ui.lua) and the home dashboard (home.lua) so the
--- detection logic lives in one place.

local M = {}

-- Sort order across task types (lower sorts first)
M.order = { task = 1, todo = 2, ask = 3, ["#todo"] = 4, ["#tech-debt"] = 5 }

--- Scan all notes under notes_dir and return the collected tasks.
--- @param notes_dir string Absolute path to the notes directory.
--- @return table[] tasks Sorted task entries: { path, title, lnum, text, line, type }
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

				local function push(type_, text, line)
					if text and text ~= "" then
						table.insert(tasks, {
							path = note_path,
							title = title,
							lnum = lnum,
							text = text,
							line = line,
							type = type_,
						})
					end
				end

				for line in file:lines() do
					-- 1. Incomplete checklist item: - [ ]
					local task_text = line:match("^%s*%- %[ %]%s*(.*)")
					if task_text and task_text ~= "" then
						push("task", task_text, line)
					end

					-- 2. Inline TODO marker (case-insensitive, e.g. "- TODO: fix this")
					local _, todo_end = line:upper():find("TODO", 1, true)
					if todo_end then
						local after = line:sub(todo_end + 1):match(":?%s*(.*)")
						push("todo", vim.trim(after), line)
					end

					-- 3. Inline ASK marker (e.g. "- ASK: confirm status").
					-- Anchored to a bullet/list start and requiring a standalone ASK + colon,
					-- so words like "asked", "task", "MASK" are not misdetected.
					local ask_text = line:match("^%s*%-%s*ASK%s*:%s*(.*)")
					if ask_text then
						push("ask", vim.trim(ask_text), line)
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

return M
