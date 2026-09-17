-- lua/notes/mcp/tools/add_subtask.lua
--- MCP tool: notes_add_subtask — headless equivalent of
--- `notes.subtask.insert_subtask()`. Writes a detail note for a new subtask
--- and inserts a nested, linked checklist line directly beneath an existing
--- parent task line, so an AI agent can build out a board note the same way
--- a human does with <leader>nta instead of hand-editing the whole file
--- through notes_update.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path

local TASK_LINE_PATTERN = "^%s*[-*]%s*%[[ xX/~%-]%]"

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end
	local title = vim.trim(args.title or "")
	if title == "" then
		return encode_checked(encode_json({ error = "title is required" }))
	end

	local abs_path = resolve_path(args.path)
	if vim.fn.filereadable(abs_path) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. args.path }))
	end

	local f = io.open(abs_path, "r")
	if not f then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end
	local content = f:read("*a")
	f:close()
	local lines = vim.split(content, "\n")

	local parent_lnum = args.parent_lnum

	if not parent_lnum then
		if not args.parent_match or args.parent_match == "" then
			return encode_checked(encode_json({
				error = "provide parent_lnum or parent_match to identify the task line to nest under",
			}))
		end
		local found = {}
		for i, l in ipairs(lines) do
			if l:match(TASK_LINE_PATTERN) and l:find(args.parent_match, 1, true) then
				table.insert(found, { lnum = i, line = l })
			end
		end
		if #found == 0 then
			return encode_checked(encode_json({ error = "no task line matched: " .. args.parent_match }))
		elseif #found > 1 then
			return encode_checked(encode_json({
				error = "parent_match is ambiguous, matched " .. #found .. " task lines; retry with parent_lnum",
				candidates = found,
			}))
		end
		parent_lnum = found[1].lnum
	end

	local parent_line = lines[parent_lnum]
	if not parent_line or not parent_line:match(TASK_LINE_PATTERN) then
		return encode_checked(encode_json({
			error = "line " .. tostring(parent_lnum) .. " is not a checklist task line",
		}))
	end

	local subtask = require("notes.subtask")
	local parent_title = subtask.parent_from_line(parent_line)

	local note_path = subtask.ensure_detail_note(title, { parent = parent_title, source = abs_path })
	if not note_path then
		return encode_checked(encode_json({ error = "could not write the detail note for: " .. title }))
	end

	local indent = (parent_line:match("^(%s*)") or "") .. "  "
	local child_text = subtask.render_child_line(title, parent_title, indent)
	if not child_text then
		return encode_checked(encode_json({ error = "failed to render checklist line" }))
	end

	table.insert(lines, parent_lnum + 1, child_text)

	local fw = io.open(abs_path, "w")
	if not fw then
		return encode_checked(encode_json({ error = "failed to write note: " .. abs_path }))
	end
	fw:write(table.concat(lines, "\n"))
	fw:close()

	return encode_checked(encode_json({
		success = true,
		board_path = abs_path,
		child_lnum = parent_lnum + 1,
		line = child_text,
		detail_note = note_path,
		parent_title = parent_title,
	}))
end

return {
	name = "notes_add_subtask",
	description = "Add a new linked subtask under an existing checklist line: writes a detail note (same shape as notes.subtask.insert_subtask's interactive flow) and inserts a nested `- [ ] [[ parent/title ]]` line directly beneath the parent task. Identify the parent line with `parent_lnum` (from notes_tasks) or a unique `parent_match` substring.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Path to the board/weekly note to insert into (relative or absolute)" },
			title = { type = "string", description = "Subtask title (used as the detail note's title and the checklist line text)" },
			parent_lnum = { type = "number", description = "1-based line number of the parent checklist line (from notes_tasks)" },
			parent_match = { type = "string", description = "Substring to uniquely identify the parent checklist line, if parent_lnum is not known" },
		},
		required = { "path", "title" },
	},
	handler = handler,
}
