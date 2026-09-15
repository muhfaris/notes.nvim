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

	-- Dedicated swap directory for note buffers (keeps .swp files out of notes dir)
	-- NOTE: 'directory' is a global-only option, so we prepend once at setup
	if vim.o.swapfile then
		local swap_dir = vim.fn.stdpath("data") .. "/notes-swap"
		if vim.fn.isdirectory(swap_dir) == 0 then
			vim.fn.mkdir(swap_dir, "p")
		end
		if not vim.o.directory:find("notes-swap", 1, true) then
			vim.o.directory = swap_dir .. "//," .. vim.o.directory
		end
	end

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
	M.history = ui.note_history

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

	-- Given a single line's text and a 0-based column inside it, return the
	-- trimmed body of the enclosing `[[ ... ]]` pair, or nil when the column is
	-- not within such a link. string.find offsets are 1-based; col is 0-based.
	local function enclosing_wiki_body(line, col)
		local pos = 1
		while true do
			local a = line:find("%[%[", pos, false)
			if not a then
				return nil
			end
			local b = line:find("%]%]", a + 2, false) -- where `]]` starts
			if not b then
				return nil
			end
			if col >= a - 1 and col <= b + 1 then
				local body = line:sub(a + 2, b - 1)
				return body:match("^%s*(.-)%s*$")
			end
			pos = b + 2
		end
	end

	-- Wraps marksman's publishDiagnostics (installed once) so that in notes
	-- buffers (paths under the notes dir) the "Link to non-existing document"
	-- diagnostic is dropped whenever notes.nvim's own resolver can locate the
	-- parent/child wiki-link target. Genuinely-broken links (unresolvable by our
	-- resolver too) keep their diagnostic. Navigation is unaffected; other LSP
	-- clients and non-notes buffers pass through untouched.
	if not _G.__notes_marksman_diag_patched then
		_G.__notes_marksman_diag_patched = true
		local orig_publish = vim.lsp.handlers["textDocument/publishDiagnostics"]
		vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, cfg)
			if not err and result and result.uri then
				local client = vim.lsp.get_client_by_id(ctx.client_id)
				local bufnr = vim.uri_to_bufnr(result.uri)
				local bufname = (vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr)) or ""
				local norm_name = vim.fn.expand(bufname):gsub("[/\\\\]+", "/")
				if
					client
					and client.name == "marksman"
					and vim.api.nvim_buf_is_valid(bufnr)
					and norm_name:sub(1, #notes_dir) == notes_dir
				then
					local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or {}
					local drop = {}
						for i, diag in ipairs(result.diagnostics or {}) do
							if diag and diag.message and diag.range then
								local ln = diag.range.start.line
								local linet = lines[ln + 1]
								-- Only engage for marksman's "target not found" warnings (its wording
								-- splits across several phrasings), never other diagnostic kinds.
								local msg = diag.message:lower()
								local is_missing = msg:find("non-exist", nil, true)
									or msg:find("not exist", nil, true)
									or msg:find("not found", nil, true)
								if is_missing and linet then
									local body = enclosing_wiki_body(linet, diag.range.start.character)
									if body and ui.resolve_wiki_link_target(body) then
										drop[i] = true
									end
								end
							end
						end
					if next(drop) then
						result = vim.deepcopy(result)
						local kept = {}
						for i, diag in ipairs(result.diagnostics or {}) do
							if not drop[i] then
								table.insert(kept, diag)
							end
						end
						result.diagnostics = kept
					end
				end
			end
			return orig_publish(err, result, ctx, cfg)
		end
	end

	if vim.o.swapfile then
		local swap_group = vim.api.nvim_create_augroup("NotesSwapExists", { clear = true })
		vim.api.nvim_create_autocmd("SwapExists", {
			group = swap_group,
			pattern = "*",
			callback = function(ev)
				local target_file = vim.fs.normalize(ev.file ~= "" and ev.file or vim.api.nvim_buf_get_name(ev.buf))
				local norm_notes_dir = vim.fs.normalize(notes_dir)

				if target_file == "" or target_file:sub(1, #norm_notes_dir) ~= norm_notes_dir then
					return
				end

				local swapfile = vim.v.swapname
				if not swapfile or swapfile == "" then
					return
				end

				local filename = vim.fn.fnamemodify(target_file ~= "" and target_file or swapfile, ":t")
				local prompt = string.format("Swap file detected for %s", filename)
				local choices_str = "&Recover\n&Edit anyway\n&Delete swap\n&Quit"
				local idx = vim.fn.confirm(prompt, choices_str, 1, "Question")

				if idx == 1 then
					vim.v.swapchoice = "r"
				elseif idx == 2 or idx == 3 then
					if vim.fn.filereadable(swapfile) == 1 then
						vim.fn.delete(swapfile)
					end
					vim.v.swapchoice = "e"
				else
					vim.v.swapchoice = "q"
				end
			end,
		})
	end

	vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
		group = group,
		pattern = { pattern_root, pattern_nested },
		callback = function(ev)
			-- Mark as notes editor buffer
			vim.b[ev.buf].notes_editor = true
			require("notes.recent").persist(ev.buf)

			if vim.o.swapfile then
				vim.bo[ev.buf].swapfile = true
			end

			-- Apply/verify markview patches
			patch_markview()

			-- Bind <CR> to follow wiki link
			vim.keymap.set("n", "<CR>", function()
				ui.follow_wiki_link()
			end, { buffer = ev.buf, desc = "Follow Wiki Link", silent = true })

			-- Bind <C-]> / gd to follow wiki/inline links when the cursor is on one,
			-- recording a tag-stack entry so <C-t> returns to the origin (like LSP),
			-- otherwise fall back to LSP go-to-definition. This keeps markdown links
			-- (whose targets marksman can't resolve, e.g. subtask parent/child bodies)
			-- working via notes.nvim's own resolver, while preserving LSP elsewhere.
			local lsp_definition = function()
				vim.lsp.buf.definition()
			end
			local jump_link_or_lsp = function()
				if ui.jump_to_link() then
					return
				end
				lsp_definition()
			end
			vim.keymap.set("n", "<C-]>", jump_link_or_lsp, {
				buffer = ev.buf,
				desc = "Follow Wiki Link / Go to Definition",
				silent = true,
			})
			vim.keymap.set("n", "gd", jump_link_or_lsp, {
				buffer = ev.buf,
				desc = "Follow Wiki Link / Go to Definition",
				silent = true,
			})

			-- Bind view history to <leader>nh (Normal mode)
			vim.keymap.set("n", "<leader>nh", function()
				ui.note_history()
			end, { buffer = ev.buf, desc = "View Note Revision History", silent = true })

			-- Bind toggle highlight to <leader>nh (Visual mode)
			vim.keymap.set("v", "<leader>nh", function()
				require("notes.formatting").toggle_highlight()
			end, { buffer = ev.buf, desc = "Toggle Markdown Highlight", silent = true })

			-- Bind toggle bold to <leader>nb (Visual mode)
			vim.keymap.set("v", "<leader>nb", function()
				require("notes.formatting").toggle_bold()
			end, { buffer = ev.buf, desc = "Toggle Markdown Bold", silent = true })

			-- Bind toggle italic to <leader>ni (Visual mode)
			vim.keymap.set("v", "<leader>ni", function()
				require("notes.formatting").toggle_italic()
			end, { buffer = ev.buf, desc = "Toggle Markdown Italic", silent = true })

			-- Bind toggle strikethrough to <leader>ns (Visual mode)
			vim.keymap.set("v", "<leader>ns", function()
				require("notes.formatting").toggle_strikethrough()
			end, { buffer = ev.buf, desc = "Toggle Markdown Strikethrough", silent = true })

			-- Bind insert hyperlink to <leader>nl (Visual mode)
			vim.keymap.set("v", "<leader>nl", function()
				require("notes.formatting").insert_link()
			end, { buffer = ev.buf, desc = "Insert Markdown Hyperlink", silent = true })

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
			require("notes.recent").persist(ev.buf)
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
