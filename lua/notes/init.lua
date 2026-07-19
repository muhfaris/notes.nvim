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
	M.quick_capture = ui.quick_capture
	M.notion_sync = function()
		require("notes.notion.sync").sync_active_note()
	end
	M.outline = ui.outline
	M.insert_toc = ui.insert_toc
	M.choose_icon = ui.choose_icon

	-- Set up global keymaps if provided in setup options
	if config.config and config.config.keymaps then
		local keymaps = config.config.keymaps
		for mode, mode_maps in pairs(keymaps) do
			for key, func_name in pairs(mode_maps) do
				if func_name and func_name ~= "" and func_name ~= false then
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

			-- Bind toggle highlight to <leader>nh
			vim.keymap.set({ "n", "v" }, "<leader>nh", function()
				require("notes.highlight").toggle_highlight()
			end, { buffer = ev.buf, desc = "Toggle Markdown Highlight", silent = true })

			-- Configure omnifunc for wiki-link completion
			vim.bo[ev.buf].omnifunc = "v:lua.require'notes.ui'.omnifunc"

			-- Initial table math refresh
			pcall(function()
				require("notes.tablemath").refresh(ev.buf)
			end)
		end,
	})

	-- Create autocommand for syntax highlighting of ==text== in note buffers
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "markdown",
		callback = function(ev)
			local buf_name = vim.api.nvim_buf_get_name(ev.buf)
			if buf_name ~= "" then
				local resolved_name = vim.fn.resolve(buf_name)
				local expanded_notes_dir = vim.fn.resolve(notes_dir)
				if resolved_name:sub(1, #expanded_notes_dir) == expanded_notes_dir then
					vim.cmd([[syntax region NotesHighlight start="==" end="==" concealends]])
					vim.cmd([[highlight default link NotesHighlight Search]])
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "TelescopePreviewerLoaded",
		callback = function(args)
			if args and args.data and args.data.bufname then
				local bufname = args.data.bufname
				if bufname ~= "" then
					local resolved_name = vim.fn.resolve(vim.fn.fnamemodify(bufname, ":p"))
					local expanded_notes_dir = vim.fn.resolve(vim.fn.fnamemodify(notes_dir, ":p"))
					if resolved_name:sub(1, #expanded_notes_dir) == expanded_notes_dir then
						vim.wo.wrap = true
					end
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		pattern = { pattern_root, pattern_nested },
		callback = function(ev)
			if config.config.auto_toc then
				require("notes.toc").update_toc(ev.buf)
			end
			pcall(function()
				require("notes.tablemath").refresh(ev.buf)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("InsertLeave", {
		group = group,
		pattern = { pattern_root, pattern_nested },
		callback = function(ev)
			pcall(function()
				require("notes.tablemath").refresh(ev.buf)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = { pattern_root, pattern_nested },
		callback = function(ev)
			local notion_opts = config.config.notion
			if notion_opts and notion_opts.enabled and notion_opts.sync_on_save then
				require("notes.notion.sync").sync_active_note_debounced(ev.buf)
			end
		end,
	})

	-- Initialize Git autocommands
	require("notes.git").setup_autocmds()
end

return M
