-- lua/notes/mcp/tools/history.lua
--- MCP tool: notes_history — git commit history for a note (or the whole
--- vault). Read-only equivalent of `notes.git.get_history`, reimplemented
--- with a blocking git call (`shared.run_git_sync`) since notes.git's
--- callback-based `vim.system` calls can't be awaited from a synchronous
--- MCP tool handler.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked
local resolve_path = shared.resolve_path
local notes_dir = shared.notes_dir

local function relative_path(abs_path)
	if abs_path:sub(1, #notes_dir) == notes_dir then
		local rel = abs_path:sub(#notes_dir + 2)
		return rel ~= "" and rel or nil
	end
	return nil
end

local function handler(args)
	if not shared.is_git_repo() then
		return encode_checked(encode_json({ error = "notes directory is not a git repository" }))
	end

	local rel_path = nil
	if args.path and args.path ~= "" then
		local abs_path = resolve_path(args.path)
		rel_path = relative_path(abs_path)
		if not rel_path then
			return encode_checked(encode_json({ error = "path is outside the notes directory: " .. args.path }))
		end
	end

	local git_args = { "log" }
	if args.limit and args.limit > 0 then
		table.insert(git_args, "-n")
		table.insert(git_args, tostring(math.floor(args.limit)))
	end
	-- --follow (survive renames) only works with exactly one pathspec, so it
	-- can't be used for vault-wide (no path) history.
	if rel_path then
		table.insert(git_args, "--follow")
	end
	table.insert(git_args, "--numstat")
	table.insert(git_args, "--date=iso-strict")
	table.insert(git_args, "--format=COMMIT:%H|%an|%ad|%s")
	if rel_path then
		table.insert(git_args, "--")
		table.insert(git_args, rel_path)
	end

	local ok, stdout, stderr = shared.run_git_sync(git_args)
	if not ok or not stdout then
		return encode_checked(encode_json({ error = stderr or "failed to read git log" }))
	end

	local history = {}
	local current = nil
	for line in stdout:gmatch("[^\r\n]+") do
		if line:sub(1, 7) == "COMMIT:" then
			if current then
				table.insert(history, current)
			end
			local hash, author, date, subject = line:sub(8):match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")
			if hash then
				current = {
					hash = hash,
					short_hash = hash:sub(1, 7),
					author = author,
					date = date,
					subject = subject ~= "" and subject or "update notes",
					additions = 0,
					deletions = 0,
				}
			end
		elseif current then
			local add, del = line:match("^(%d+)%s+(%d+)%s+")
			if add and del then
				current.additions = current.additions + tonumber(add)
				current.deletions = current.deletions + tonumber(del)
			end
		end
	end
	if current then
		table.insert(history, current)
	end

	return encode_checked(encode_json({ path = rel_path, commits = history, count = #history }))
end

return {
	name = "notes_history",
	description = "List git commit history for a note (hash, author, date, subject, lines added/removed per commit), or for the whole vault if no path is given. Requires the notes directory to be a git repository. Pass a commit's `hash` to notes_diff to see what changed.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Optional note path (relative or absolute); omit for vault-wide history" },
			limit = { type = "number", description = "Optional max number of commits to return" },
		},
		required = {},
	},
	handler = handler,
}
