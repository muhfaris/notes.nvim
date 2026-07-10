local config = require("notes.config")
if vim.fn.has("nvim-0.7.0") == 0 then
	vim.api.nvim_err_writeln("Notes requires at least nvim-0.7.0.+")
	return
end

-- prevent loading file twice
if vim.g.loaded_notes == 1 then
	return
end
vim.g.loaded_notes = 1

-- Create the main :Notes command with subcommands
vim.api.nvim_create_user_command("Notes", function(opts)
	local subcmd = opts.fargs[1]
	-- Normalize dash/underscore for paste_image
	if subcmd == "paste-image" then
		subcmd = "paste_image"
	end

	-- Handle daily prev / daily next
	if subcmd == "daily" and opts.fargs[2] then
		if opts.fargs[2] == "prev" then
			subcmd = "daily_prev"
		elseif opts.fargs[2] == "next" then
			subcmd = "daily_next"
		end
	end

	local fn = config.config.fn[subcmd]
	if fn then
		-- Pass remaining fargs as arguments to the function (e.g. title)
		local args = {}
		local start_idx = 2
		if subcmd == "daily_prev" or subcmd == "daily_next" then
			start_idx = 3
		end
		for i = start_idx, #opts.fargs do
			table.insert(args, opts.fargs[i])
		end
		fn(table.concat(args, " "))
	else
		vim.api.nvim_err_writeln("Invalid notes subcommand. Available commands: new, daily, list, explorer, search, paste_image, migrate, tags, rename, delete, backlinks, tasks")
	end
end, {
	nargs = "+",
	complete = function(ArgLead, CmdLine, CursorPos)
		local parts = {}
		for _, part in ipairs(vim.split(CmdLine, "%s+")) do
			if part ~= "" then
				table.insert(parts, part)
			end
		end

		local is_daily_subcmd = false
		if #parts >= 2 and parts[2] == "daily" then
			if #parts == 3 or (#parts == 2 and CmdLine:match("%s+$")) then
				is_daily_subcmd = true
			end
		end

		if is_daily_subcmd then
			local daily_sub = { "prev", "next" }
			return vim.tbl_filter(function(cmd)
				return cmd:match("^" .. ArgLead)
			end, daily_sub)
		end

		local subcommands = { "new", "daily", "list", "explorer", "search", "paste_image", "migrate", "tags", "rename", "delete", "backlinks", "tasks" }
		return vim.tbl_filter(function(cmd)
			return cmd:match("^" .. ArgLead)
		end, subcommands)
	end,
})

