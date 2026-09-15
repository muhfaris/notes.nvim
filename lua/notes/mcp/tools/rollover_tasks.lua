-- lua/notes/mcp/tools/rollover_tasks.lua
--- MCP tool: notes_rollover_tasks — carry forward unfinished checklist items
--- from one board note into a new note, so a new week/period doesn't start
--- by retyping last week's open items.
---
--- A line is carried when its own checkbox is not done (`[ ]`/`[/]`/`[~]`),
--- or when it is an ancestor (by indentation) of a carried line — so a
--- parent category stays as context for a still-open child even if the
--- category's own box reads " ". Headings are carried only when at least
--- one line under them was carried.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path

local function handler(args)
	if not args.from_path or args.from_path == "" then
		return encode_checked(encode_json({ error = "from_path is required" }))
	end
	local title = vim.trim(args.title or "")
	if title == "" then
		return encode_checked(encode_json({ error = "title is required" }))
	end

	local abs_from = resolve_path(args.from_path)
	if vim.fn.filereadable(abs_from) ~= 1 then
		return encode_checked(encode_json({ error = "note not found: " .. args.from_path }))
	end

	local f = io.open(abs_from, "r")
	if not f then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_from }))
	end
	local lines = {}
	for line in f:lines() do
		table.insert(lines, line)
	end
	f:close()

	-- Pass 1: mark every checklist line that is not done, plus its chain of
	-- task-line ancestors (by indentation), as "keep".
	local keep = {}
	local indent_of = {}
	local stack = {} -- ancestor task-line indices, outermost first
	for i, line in ipairs(lines) do
		local indent, box = line:match("^(%s*)[-*]%s*%[(.)%]")
		if box then
			indent_of[i] = #indent
			while #stack > 0 and indent_of[stack[#stack]] >= #indent do
				table.remove(stack)
			end
			local not_done = box == " " or box == "/" or box == "~"
			if not_done then
				keep[i] = true
				for _, anc in ipairs(stack) do
					keep[anc] = true
				end
			end
			table.insert(stack, i)
		end
	end

	-- Pass 2: keep a heading line if any line before the next heading of
	-- equal-or-higher level is kept. The note's own H1 title is excluded: it
	-- is an "ancestor" of every section by nesting depth, so carrying it
	-- forward would just duplicate the title line the caller already set.
	local heading_lines, heading_level = {}, {}
	for i, line in ipairs(lines) do
		local hashes = line:match("^(#+)%s")
		if hashes and #hashes > 1 then
			table.insert(heading_lines, i)
			heading_level[i] = #hashes
		end
	end
	for idx, i in ipairs(heading_lines) do
		local level = heading_level[i]
		local stop = #lines
		for j = idx + 1, #heading_lines do
			if heading_level[heading_lines[j]] <= level then
				stop = heading_lines[j] - 1
				break
			end
		end
		for j = i + 1, stop do
			if keep[j] then
				keep[i] = true
				break
			end
		end
	end

	local carried = {}
	for i, line in ipairs(lines) do
		if keep[i] then
			table.insert(carried, line)
		end
	end

	if #carried == 0 then
		return encode_checked(encode_json({
			success = true,
			carried_count = 0,
			message = "no unfinished tasks found in " .. args.from_path,
		}))
	end

	local from_metadata = require("notes.parser").read_file(abs_from)
	local from_title = (from_metadata and from_metadata.title and from_metadata.title ~= "") and from_metadata.title
		or vim.fn.fnamemodify(abs_from, ":t:r")

	local body_lines = { "Previous: [[ " .. from_title .. " ]]", "", "## Carried Forward" }
	for _, l in ipairs(carried) do
		table.insert(body_lines, l)
	end

	local create_tool = require("notes.mcp.tools.create")
	local result = shared.decode_json(create_tool.handler({
		title = title,
		content = table.concat(body_lines, "\n"),
		tags = args.tags,
		directory = args.directory,
	}))
	if not result or result.error then
		return encode_checked(encode_json({ error = (result and result.error) or "failed to create new note" }))
	end

	return encode_checked(encode_json({
		success = true,
		path = result.path,
		title = result.title,
		carried_count = #carried,
	}))
end

return {
	name = "notes_rollover_tasks",
	description = "Create a new note that carries forward every not-done checklist item (`- [ ]`/`- [/]`/`- [~]`) from an existing board note, keeping each item's heading and parent-task context. Use at the start of a new week/period instead of retyping last period's open items.",
	inputSchema = {
		type = "object",
		properties = {
			from_path = { type = "string", description = "Path to the previous board/weekly note to carry tasks forward from" },
			title = { type = "string", description = "Title for the new note" },
			directory = { type = "string", description = "Optional subdirectory under notes for the new note; defaults to notes root" },
			tags = { type = "array", items = { type = "string" }, description = "Optional tags for the new note" },
		},
		required = { "from_path", "title" },
	},
	handler = handler,
}
