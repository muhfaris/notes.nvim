-- lua/notes/mcp/tools/diff.lua
--- MCP tool: notes_diff — the git diff introduced by one commit, optionally
--- scoped to a single note. Read-only equivalent of
--- `notes.git.get_commit_diff`, reimplemented with a blocking git call (see
--- notes_history for why).

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
	if not args.commit or args.commit == "" then
		return encode_checked(encode_json({ error = "commit is required (a hash from notes_history)" }))
	end
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

	local git_args = { "show", "--format=", args.commit }
	if rel_path then
		table.insert(git_args, "--")
		table.insert(git_args, rel_path)
	end

	local ok, stdout, stderr = shared.run_git_sync(git_args)
	if not ok or stdout == nil or stdout == "" then
		return encode_checked(encode_json({ error = stderr or "failed to retrieve commit diff" }))
	end

	return encode_checked(encode_json({ commit = args.commit, path = rel_path, diff = stdout }))
end

return {
	name = "notes_diff",
	description = "Show the git diff introduced by a commit (hash from notes_history), optionally scoped to one note's path.",
	inputSchema = {
		type = "object",
		properties = {
			commit = { type = "string", description = "Commit hash (from notes_history)" },
			path = { type = "string", description = "Optional note path to scope the diff to (relative or absolute)" },
		},
		required = { "commit" },
	},
	handler = handler,
}
