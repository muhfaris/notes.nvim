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

-- Create the main :notes command with subcommands
vim.api.nvim_create_user_command("Notes", function(opts)
	local fn = config.config.fn[opts.fargs[1]]
	if fn then
		fn()
	else
		vim.api.nvim_err_writeln("Invalid notes subcommand. Available commands: new, list, find, paste-image")
	end
end, {
	nargs = "+",
	complete = function(ArgLead, CmdLine, CursorPos)
		local subcommands = { "new", "list", "find_by_keyword", "paste-image" }
		return vim.tbl_filter(function(cmd)
			return cmd:match("^" .. ArgLead)
		end, subcommands)
	end,
})
