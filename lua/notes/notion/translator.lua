-- lua/notes/notion/translator.lua
local M = {}

--- Helper to create a Notion text block helper.
local function text_block(type_name, content, extra_fields)
	local block = {
		object = "block",
		type = type_name,
	}
	block[type_name] = {
		rich_text = {
			{
				type = "text",
				text = { content = content },
			},
		},
	}
	if extra_fields then
		for k, v in pairs(extra_fields) do
			block[type_name][k] = v
		end
	end
	return block
end

--- Map markdown code blocks to Notion's accepted languages.
local function clean_language(lang)
	if not lang or lang == "" then
		return "plain text"
	end
	lang = lang:lower():gsub("%s+", "")
	local supported = {
		abap = true, arduino = true, bash = true, basic = true, c = true, clojure = true,
		coffeescript = true, cpp = true, csharp = true, css = true, dart = true, diff = true,
		docker = true, elixir = true, elm = true, erlang = true, flow = true, fortran = true,
		fsharp = true, gherkin = true, glsl = true, go = true, graphql = true, groovy = true,
		haskell = true, html = true, java = true, javascript = true, json = true, julia = true,
		kotlin = true, latex = true, less = true, lisp = true, livescript = true, lua = true,
		makefile = true, markdown = true, markup = true, matlab = true, nix = true, objectivec = true,
		ocaml = true, pascal = true, perl = true, php = true, plaintext = true, powershell = true,
		prolog = true, protobuf = true, python = true, r = true, reason = true, ruby = true,
		rust = true, sass = true, scala = true, scheme = true, scss = true, shell = true,
		sql = true, swift = true, typescript = true, vbnet = true, verilog = true, vhdl = true,
		visualbasic = true, webassembly = true, xml = true, yaml = true
	}
	if lang == "sh" then return "shell" end
	if lang == "js" then return "javascript" end
	if lang == "ts" then return "typescript" end
	if lang == "cs" then return "csharp" end
	if lang == "py" then return "python" end
	if lang == "rb" then return "ruby" end

	if supported[lang] then
		return lang
	end
	return "plain text"
end

--- Parse note markdown body text and translate into Notion blocks.
--- @param content string The raw note body (YAML frontmatter excluded).
--- @return table An array of Notion blocks.
function M.translate_to_blocks(content)
	local blocks = {}
	local current_paragraph = nil

	-- Code block state tracker
	local in_code_block = false
	local code_lines = {}
	local code_lang = "plain text"

	local function flush_paragraph()
		if current_paragraph then
			table.insert(blocks, text_block("paragraph", table.concat(current_paragraph, "\n")))
			current_paragraph = nil
		end
	end

	-- Split content by lines
	local lines = vim.split(content, "\r?\n")

	for _, line in ipairs(lines) do
		-- Handle code block logic
		if in_code_block then
			if line:match("^```%s*$") then
				-- Code block ends
				local code_content = table.concat(code_lines, "\n")
				table.insert(blocks, text_block("code", code_content, { language = code_lang }))
				in_code_block = false
				code_lines = {}
			else
				table.insert(code_lines, line)
			end
		else
			-- We are not in a code block
			local lang_match = line:match("^```(%S*)%s*$")
			if lang_match then
				flush_paragraph()
				in_code_block = true
				code_lang = clean_language(lang_match)
			elseif line:match("^#%s+(.*)$") then
				flush_paragraph()
				local text = line:match("^#%s+(.*)$")
				table.insert(blocks, text_block("heading_1", text))
			elseif line:match("^##%s+(.*)$") then
				flush_paragraph()
				local text = line:match("^##%s+(.*)$")
				table.insert(blocks, text_block("heading_2", text))
			elseif line:match("^###%s+(.*)$") then
				flush_paragraph()
				local text = line:match("^###%s+(.*)$")
				table.insert(blocks, text_block("heading_3", text))
			elseif line:match("^%-?%s*%[([xX%s])%]%s+(.*)$") then
				flush_paragraph()
				local checked_char, text = line:match("^%-?%s*%[([xX%s])%]%s+(.*)$")
				local checked = (checked_char == "x" or checked_char == "X")
				table.insert(blocks, text_block("to_do", text, { checked = checked }))
			elseif line:match("^%-%s+(.*)$") or line:match("^%*%s+(.*)$") or line:match("^%+%s+(.*)$") then
				flush_paragraph()
				local text = line:match("^[%-%*%+]%s+(.*)$")
				table.insert(blocks, text_block("bulleted_list_item", text))
			elseif line:match("^%d+[%.%)]%s+(.*)$") then
				flush_paragraph()
				local text = line:match("^%d+[%.%)]%s+(.*)$")
				table.insert(blocks, text_block("numbered_list_item", text))
			elseif line:match("^%s*$") then
				flush_paragraph()
			else
				-- It's standard paragraph text
				if not current_paragraph then
					current_paragraph = {}
				end
				table.insert(current_paragraph, line)
			end
		end
	end

	-- Flush any remaining code blocks or paragraphs at the end of the file
	if in_code_block then
		local code_content = table.concat(code_lines, "\n")
		table.insert(blocks, text_block("code", code_content, { language = code_lang }))
	else
		flush_paragraph()
	end

	-- Clean up trailing empty paragraphs
	while #blocks > 0 and blocks[#blocks].type == "paragraph" and #blocks[#blocks].paragraph.rich_text == 0 do
		table.remove(blocks)
	end

	return blocks
end

return M
