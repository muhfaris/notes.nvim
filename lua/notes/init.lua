local M = {}

local function safe_require(module)
	local ok, result = pcall(require, module)
	if not ok then
		error(string.format("Failed to load %s: %s", module, result))
	end
	if type(result) ~= "table" then
		error(string.format("Module %s did not return a table", module))
	end
	return result
end

local function patch_markview()
	local ok_wrap, mv_wrap = pcall(require, "markview.wrap")
	if ok_wrap and type(mv_wrap) == "table" then
		if not mv_wrap.__patched_for_notes then
			local orig_wrap_indent = mv_wrap.wrap_indent
			mv_wrap.wrap_indent = function(buffer, range, indent)
				if vim.b[buffer] and vim.b[buffer].notes_editor then
					return
				end
				if orig_wrap_indent then
					return orig_wrap_indent(buffer, range, indent)
				end
			end
			mv_wrap.__patched_for_notes = true
		end
	end

	local ok_actions, mv_actions = pcall(require, "markview.actions")
	if ok_actions and type(mv_actions) == "table" then
		if not mv_actions.__patched_for_notes then
			local orig_uses_wrap_support = mv_actions.uses_wrap_support
			mv_actions.uses_wrap_support = function()
				local buf = vim.api.nvim_get_current_buf()
				if vim.b[buf] and vim.b[buf].notes_editor then
					return false
				end
				if orig_uses_wrap_support then
					return orig_uses_wrap_support()
				end
				return false
			end
			mv_actions.__patched_for_notes = true
		end
	end
end

M.setup = function(opts)
	local config = require("notes.config")
	config.setup(opts)

	-- Apply markview patches if present
	patch_markview()

	-- Expose APIs
	local ui = safe_require("notes.ui")
	local utils = safe_require("notes.utils")

	M.new_note = ui.new_note
	M.daily_note = ui.daily_note
	M.list_notes = ui.list_notes
	M.toggle_explorer = ui.toggle_explorer
	M.search_notes = ui.search_notes
	M.paste_image = utils.paste_image
	M.follow_wiki_link = ui.follow_wiki_link

	-- Set up global keymaps if provided in setup options
	if config.config and config.config.keymaps then
		local keymaps = config.config.keymaps
		for mode, mode_maps in pairs(keymaps) do
			for key, func_name in pairs(mode_maps) do
				local desc = config.config.key_desc[func_name] or "No description from notes.nvim"
				if config.config.fn[func_name] then
					vim.keymap.set(
						mode,
						key,
						config.config.fn[func_name],
						{ noremap = true, silent = true, desc = desc }
					)
				else
					vim.notify("Function " .. func_name .. " not found in notes plugin", vim.log.levels.WARN)
				end
			end
		end
	end

	-- Create autocommands to bind buffer-local mappings in note buffers
	local group = vim.api.nvim_create_augroup("NotesBufferLocalMappings", { clear = true })
	local notes_dir = vim.fn.expand(config.config.notes_dir):gsub("/+$", "")
	local pattern_root = notes_dir .. "/*.md"
	local pattern_nested = notes_dir .. "/**/*.md"

	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = group,
		pattern = { pattern_root, pattern_nested },
		callback = function(ev)
			-- Mark as notes editor buffer
			vim.b[ev.buf].notes_editor = true

			-- Apply/verify markview patches
			patch_markview()

			-- Bind <CR> to follow wiki link
			vim.keymap.set("n", "<CR>", function()
				ui.follow_wiki_link()
			end, { buffer = ev.buf, desc = "Follow Wiki Link", silent = true })

			-- Bind toggle task to <leader>nt
			vim.keymap.set("n", "<leader>nt", function()
				require("notes.tasks").toggle_task()
			end, { buffer = ev.buf, desc = "Toggle Markdown Task", silent = true })
		end,
	})
end

return M
