-- lua/notes/git.lua
local M = {}
local config = require("notes.config").get_config()

-- Helper to run an async git command
local function run_git(args, callback)
	if vim.fn.executable("git") ~= 1 then
		if callback then callback(false, "git not found") end
		return
	end

	local cmd = { "git", "-C", config.notes_dir }
	for _, arg in ipairs(args) do
		table.insert(cmd, arg)
	end

	vim.system(cmd, {}, function(obj)
		if callback then
			callback(obj.code == 0, obj.stdout, obj.stderr)
		end
	end)
end

-- Checks if git is set up, enabled, and the notes dir is a git repo
-- Automatically initializes a git repository if it is not yet initialized
function M.check_repo(callback)
	if not config.git or not config.git.enabled then
		if callback then callback(false, "git integration not enabled") end
		return
	end

	if vim.fn.executable("git") ~= 1 then
		if callback then callback(false, "git executable not found") end
		return
	end

	run_git({ "rev-parse", "--is-inside-work-tree" }, function(is_repo)
		if is_repo then
			if callback then callback(true) end
		else
			-- Auto-initialize Git repository
			run_git({ "init" }, function(init_success)
				if init_success then
					vim.schedule(function()
						vim.notify("Initialized Git repository in notes directory: " .. config.notes_dir, vim.log.levels.INFO)
					end)
					if callback then callback(true) end
				else
					if callback then callback(false, "failed to initialize git repository") end
				end
			end)
		end
	end)
end

-- Performs git add & commit if there are modified/untracked/deleted files
function M.commit(custom_message, is_auto)
	if is_auto and config.git and config.git.auto_commit == false then
		return
	end

	M.check_repo(function(is_repo)
		if not is_repo then return end

		-- Check if there are any changes (modified, untracked, or deleted files)
		run_git({ "status", "--porcelain" }, function(success, stdout)
			if not success or not stdout or vim.trim(stdout) == "" then
				return
			end

			-- Stage all changes
			run_git({ "add", "-A" }, function(add_success)
				if not add_success then return end

				local base_msg = custom_message or (config.git and config.git.commit_message or "update notes")
				local timestamp = os.date("%Y-%m-%d %H:%M:%S")
				local msg = base_msg .. " (" .. timestamp .. ")"

				-- Commit asynchronously
				run_git({ "commit", "-m", msg }, function(commit_success)
					if commit_success then
						vim.schedule(function()
							vim.notify("Notes committed: " .. msg, vim.log.levels.INFO)
						end)
					end
				end)
			end)
		end)
	end)
end

-- Sets up the autocommands for Git integration
function M.setup_autocmds()
	if not config.git or not config.git.enabled then
		return
	end

	local group = vim.api.nvim_create_augroup("NotesGitSync", { clear = true })

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(args)
			local buf_name = vim.api.nvim_buf_get_name(args.buf)
			if buf_name == "" then return end
			local abs_path = vim.fn.resolve(buf_name)
			local notes_abs = vim.fn.resolve(config.notes_dir)
			
			if abs_path:sub(1, #notes_abs) == notes_abs and abs_path:match("%.md$") then
				M.commit(nil, true)
			end
		end,
	})
end

-- Returns relative path of filepath with respect to config.notes_dir
function M.get_relative_path(filepath)
	if not filepath or filepath == "" then
		return nil
	end
	local abs_file = vim.fn.resolve(filepath)
	local notes_abs = vim.fn.resolve(config.notes_dir):gsub("/+$", "")
	if abs_file:sub(1, #notes_abs) == notes_abs then
		local rel = abs_file:sub(#notes_abs + 2)
		return rel ~= "" and rel or nil
	end
	return nil
end

-- Helper to format ISO date string into human-readable relative date (e.g., "2 hours ago")
local function format_relative_date(date_str)
	if not date_str or date_str == "" then
		return ""
	end
	-- Parse ISO timestamp if possible
	local y, m, d, h, min, s = date_str:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
	if y and m and d and h and min and s then
		local commit_time = os.time({
			year = tonumber(y),
			month = tonumber(m),
			day = tonumber(d),
			hour = tonumber(h),
			min = tonumber(min),
			sec = tonumber(s),
		})
		local diff = os.time() - commit_time
		if diff < 60 then
			return "just now"
		elseif diff < 3600 then
			local mins = math.floor(diff / 60)
			return mins .. (mins == 1 and " min ago" or " mins ago")
		elseif diff < 86400 then
			local hours = math.floor(diff / 3600)
			return hours .. (hours == 1 and " hour ago" or " hours ago")
		elseif diff < 604800 then
			local days = math.floor(diff / 86400)
			return days .. (days == 1 and " day ago" or " days ago")
		else
			return string.format("%04d-%02d-%02d %02d:%02d", y, m, d, h, min)
		end
	end
	return date_str
end

-- Fetches commit history for a file or entire vault asynchronously
function M.get_history(filepath, callback)
	M.check_repo(function(is_repo, err)
		if not is_repo then
			if callback then callback(false, err or "Git repository not active") end
			return
		end

		local rel_path = filepath and M.get_relative_path(filepath) or nil
		local args = { "log", "--follow", "--numstat", "--date=iso-strict", "--format=COMMIT:%H|%an|%ad|%s" }
		if rel_path then
			table.insert(args, "--")
			table.insert(args, rel_path)
		end

		run_git(args, function(success, stdout, stderr)
			if not success or not stdout then
				if callback then callback(false, stderr or "Failed to read git log") end
				return
			end

			local history = {}
			local current_commit = nil

			for line in stdout:gmatch("[^\r\n]+") do
				if line:sub(1, 7) == "COMMIT:" then
					if current_commit then
						table.insert(history, current_commit)
					end
					local hash, author, date, subject = line:sub(8):match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")
					if hash then
						current_commit = {
							hash = hash,
							short_hash = hash:sub(1, 7),
							author = author,
							date = date,
							relative_date = format_relative_date(date),
							subject = subject ~= "" and subject or "update notes",
							additions = 0,
							deletions = 0,
							rel_path = rel_path,
						}
					end
				elseif current_commit then
					local add, del = line:match("^(%d+)%s+(%d+)%s+")
					if add and del then
						current_commit.additions = current_commit.additions + tonumber(add)
						current_commit.deletions = current_commit.deletions + tonumber(del)
					end
				end
			end
			if current_commit then
				table.insert(history, current_commit)
			end

			if callback then callback(true, history) end
		end)
	end)
end

-- Retrieves full file content at a specific commit hash
function M.get_file_at_commit(filepath, commit_hash, callback)
	local rel_path = M.get_relative_path(filepath)
	if not rel_path then
		if callback then callback(false, "File outside notes directory") end
		return
	end

	local spec = string.format("%s:%s", commit_hash, rel_path)
	run_git({ "show", spec }, function(success, stdout, stderr)
		if success and stdout then
			if callback then callback(true, stdout) end
		else
			if callback then callback(false, stderr or "Failed to retrieve snapshot") end
		end
	end)
end

-- Retrieves git diff output for a commit relative to its parent
function M.get_commit_diff(filepath, commit_hash, callback)
	local rel_path = M.get_relative_path(filepath)
	local args = { "show", "--format=", commit_hash }
	if rel_path then
		table.insert(args, "--")
		table.insert(args, rel_path)
	end

	run_git(args, function(success, stdout, stderr)
		if success and stdout then
			if callback then callback(true, stdout) end
		else
			if callback then callback(false, stderr or "Failed to retrieve commit diff") end
		end
	end)
end

return M
