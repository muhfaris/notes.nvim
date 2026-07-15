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

return M
