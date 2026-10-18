-- lua/notes/mcp/tools/export_html.lua
--- MCP tool: notes_export_html — render one note to a standalone HTML file.
---
--- Pandoc is used when installed (tables, task lists, full Markdown), with a
--- dependency-free fallback for headings, lists, checkboxes, code, quotes,
--- links, images, and wiki-links. The result is a self-contained file with
--- inline CSS, so a browser can open it without a server.

local shared = require("notes.mcp.shared")
local encode_json, encode_checked = shared.encode_json, shared.encode_checked

local function escape_html(text)
	return (
		tostring(text or "")
			:gsub("&", "&amp;")
			:gsub("<", "&lt;")
			:gsub(">", "&gt;")
			:gsub('"', "&quot;")
	)
end

local function file_url(path)
	return "file://" .. path:gsub(" ", "%%20"):gsub("#", "%%23"):gsub("%?", "%%3F")
end

local function safe_href(url)
	local value = vim.trim(tostring(url or ""))
	local lower = value:lower()
	if
		lower:match("^javascript:")
		or lower:match("^vbscript:")
		or lower:match("^data:text/html")
		or lower:match("^data:application/")
		or lower:match("^data:image/svg%+xml")
	then
		return "#"
	end
	return value
end

--- Resolve a note-relative image to an absolute file URL so the exported HTML
--- (which lives outside the note's folder) can still load it.
local function resolve_image(src, note_dir)
	local value = vim.trim(tostring(src or ""))
	if value == "" or value:match("^%a[%w+.-]*:") or value:sub(1, 2) == "//" then
		return value
	end
	local candidate = value:sub(1, 1) == "/" and value or (note_dir .. "/" .. value)
	candidate = vim.fn.fnamemodify(candidate, ":p")
	if vim.fn.filereadable(candidate) == 1 then
		return file_url(candidate)
	end
	return value
end

local function render_inline(text, note_dir)
	text = escape_html(text)
	local saved = {}

	local function protect(html)
		local key = "\1" .. #saved .. "\2"
		saved[#saved + 1] = html
		return key
	end

	-- Protect code/links/images/wiki-links before applying emphasis, so
	-- generated tags and their contents cannot be re-parsed as markdown.
	text = text:gsub("`([^`]+)`", function(code)
		return protect("<code>" .. code .. "</code>")
	end)
	text = text:gsub("!%[([^%]]*)%]%(([^%)]+)%)", function(alt, src)
		return protect('<img src="' .. safe_href(resolve_image(src, note_dir)) .. '" alt="' .. alt .. '">')
	end)
	text = text:gsub("%[([^%]]*)%]%(([^%)]+)%)", function(label, url)
		return protect('<a href="' .. safe_href(url) .. '">' .. label .. "</a>")
	end)
	text = text:gsub("%[%[%s*(.-)%s*%]%]", function(body)
		local label = body:match("|%s*(.-)%s*$")
		if not label or vim.trim(label) == "" then
			label = vim.trim(body):match("([^/]+)$") or body
		end
		return protect('<span class="wikilink">' .. vim.trim(label) .. "</span>")
	end)

	text = text:gsub("%*%*([^%*]+)%*%*", "<strong>%1</strong>")
	text = text:gsub("__([^_]+)__", "<strong>%1</strong>")
	text = text:gsub("~~([^~]+)~~", "<del>%1</del>")
	text = text:gsub("%*([^%*]+)%*", "<em>%1</em>")
	text = text:gsub("_([^_]+)_", "<em>%1</em>")

	for i = #saved, 1, -1 do
		text = text:gsub("\1" .. (i - 1) .. "\2", function()
			return saved[i]
		end)
	end
	return text
end

local function render_markdown(body, note_dir)
	local out = {}
	local lines = vim.split(body or "", "\n")
	local i = 1

	while i <= #lines do
		local line = lines[i]
		local fence, lang = line:match("^```(%S*)%s*$")

		if fence then
			local code = {}
			i = i + 1
			while i <= #lines and not lines[i]:match("^```%s*$") do
				table.insert(code, lines[i])
				i = i + 1
			end
			i = i + 1
			local class = lang ~= "" and (' class="language-' .. escape_html(lang) .. '"') or ""
			table.insert(out, "<pre><code" .. class .. ">" .. escape_html(table.concat(code, "\n")) .. "</code></pre>")
		elseif line:match("^%s*$") then
			i = i + 1
		else
			local hashes, heading = line:match("^(#+)%s+(.*)$")
			if hashes then
				local level = math.min(#hashes, 6)
				table.insert(out, "<h" .. level .. ">" .. render_inline(heading, note_dir) .. "</h" .. level .. ">")
				i = i + 1
			elseif line:match("^%s*%-%-%-+%s*$") then
				table.insert(out, "<hr>")
				i = i + 1
			elseif line:match("^%s*>") then
				local quote = {}
				while i <= #lines and lines[i]:match("^%s*>") do
					table.insert(quote, (lines[i]:gsub("^%s*>%s?", "")))
					i = i + 1
				end
				table.insert(
					out,
					"<blockquote>" .. (render_inline(table.concat(quote, "\n"), note_dir):gsub("\n", "<br>")) .. "</blockquote>"
				)
			elseif line:match("^%s*[%-%*%+]%s+") or line:match("^%s*%d+%.%s+") then
				local items = {}
				while i <= #lines and (lines[i]:match("^%s*[%-%*%+]%s+") or lines[i]:match("^%s*%d+%.%s+")) do
					local item = lines[i]
					local indent = #(item:match("^(%s*)") or "")
					local text = (item:gsub("^%s*[%-%*%+]%s+", ""):gsub("^%s*%d+%.%s+", ""))
					local box = text:match("^%[(.)%]%s*(.*)$")
					local marker
					if box then
						local rest = text:match("^%[.%]%s*(.*)$") or ""
						text = rest
						if box == " " or box == "x" or box == "X" then
							local checked = (box == "x" or box == "X") and " checked" or ""
							marker = '<input type="checkbox" disabled' .. checked .. ">"
						else
							local glyph = (box == "/" or box == "~") and "◐" or (box == "?" and "?" or "✕")
							marker = '<span class="box">' .. glyph .. "</span>"
						end
					else
						marker = '<span class="bullet">•</span>'
					end
					table.insert(
						items,
						'<div class="li" style="margin-left:'
							.. string.format("%.1f", indent * 0.5)
							.. 'em">'
							.. marker
							.. " "
							.. render_inline(text, note_dir)
							.. "</div>"
					)
					i = i + 1
				end
				table.insert(out, table.concat(items, "\n"))
			else
				local para = {}
				while
					i <= #lines
					and lines[i]:match("%S")
					and not lines[i]:match("^#+%s")
					and not lines[i]:match("^```")
					and not lines[i]:match("^%s*[%-%*%+]%s+")
					and not lines[i]:match("^%s*%d+%.%s+")
					and not lines[i]:match("^%s*>")
					and not lines[i]:match("^%s*%-%-%-+%s*$")
				do
					table.insert(para, lines[i])
					i = i + 1
				end
				table.insert(out, "<p>" .. (render_inline(table.concat(para, "\n"), note_dir):gsub("\n", "<br>")) .. "</p>")
			end
		end
	end

	return table.concat(out, "\n")
end

local function preprocess_for_pandoc(body, note_dir)
	local wiki = {}
	body = body:gsub("%[%[%s*(.-)%s*%]%]", function(raw)
		local label = raw:match("|%s*(.-)%s*$")
		if not label or vim.trim(label) == "" then
			label = vim.trim(raw):match("([^/]+)$") or raw
		end
		wiki[#wiki + 1] = escape_html(vim.trim(label))
		return "XWIKILINKTOKEN" .. (#wiki - 1) .. "X"
	end)
	body = body:gsub("!%[([^%]]*)%]%(([^%)]+)%)", function(alt, src)
		return "![" .. alt .. "](" .. resolve_image(src, note_dir) .. ")"
	end)
	return body, wiki
end

local function sanitize_hrefs(html)
	html = html:gsub('href="([^"]*)"', function(url)
		return 'href="' .. safe_href(url) .. '"'
	end)
	html = html:gsub('src="([^"]*)"', function(url)
		return 'src="' .. safe_href(url) .. '"'
	end)
	return html
end

local function render_with_pandoc(body, note_dir)
	if vim.fn.executable("pandoc") ~= 1 then
		return nil
	end
	local prepared, wiki = preprocess_for_pandoc(body, note_dir)
	local tmp = vim.fn.tempname() .. ".md"
	local f = io.open(tmp, "w")
	if not f then
		return nil
	end
	f:write(prepared)
	f:close()

	local obj = vim.system({ "pandoc", "-f", "markdown-raw_html", "-t", "html5", "--wrap=none", tmp }, { text = true }):wait()
	os.remove(tmp)

	if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then
		return nil
	end

	local html = obj.stdout:gsub("XWIKILINKTOKEN(%d+)X", function(index)
		local label = wiki[tonumber(index) + 1]
		return label and ('<span class="wikilink">' .. label .. "</span>") or ""
	end)
	return sanitize_hrefs(html)
end

local function html_document(title, metadata, body)
	local meta = {}
	if metadata.date and metadata.date ~= "" then
		table.insert(meta, escape_html(metadata.date))
	end
	if type(metadata.tags) == "table" and #metadata.tags > 0 then
		local tags = {}
		for _, tag in ipairs(metadata.tags) do
			table.insert(tags, escape_html(tag))
		end
		table.insert(meta, table.concat(tags, ", "))
	end
	local meta_html = #meta > 0 and ('<p class="meta">' .. table.concat(meta, " · ") .. "</p>") or ""

	return table.concat({
		"<!doctype html>",
		'<html lang="en">',
		"<head>",
		'<meta charset="utf-8">',
		'<meta name="viewport" content="width=device-width, initial-scale=1">',
		"<title>" .. escape_html(title) .. "</title>",
		[[<style>
:root { color-scheme: light dark; }
body { margin: 0; padding: 2rem 1rem; font: 16px/1.65 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 860px; margin: 0 auto; }
h1, h2, h3, h4 { line-height: 1.25; margin-top: 1.6em; }
p.meta { color: #777; font-size: .9rem; margin: -.4rem 0 1.4rem; }
code { background: rgba(127,127,127,.15); padding: .12em .35em; border-radius: 4px; }
pre { background: rgba(127,127,127,.12); padding: 1rem; overflow: auto; border-radius: 6px; }
pre code { background: none; padding: 0; }
blockquote { margin: 1rem 0; padding: .2rem 1rem; border-left: 3px solid #888; color: #666; }
hr { border: 0; border-top: 1px solid rgba(127,127,127,.35); margin: 2rem 0; }
.wikilink { border-bottom: 1px dotted currentColor; }
.li { margin: .2rem 0; }
.li input { margin-right: .45rem; }
.box { display: inline-block; width: 1.1em; text-align: center; }
img { max-width: 100%; height: auto; }
table { border-collapse: collapse; }
th, td { border: 1px solid rgba(127,127,127,.4); padding: .35rem .6rem; }
@media (prefers-color-scheme: dark) {
  body { background: #1b1e24; color: #d7dae0; }
  p.meta, blockquote { color: #9aa0aa; }
  a { color: #7aa2f7; }
}
</style>]],
		"</head>",
		"<body><main>",
		meta_html,
		body,
		"</main></body></html>",
	}, "\n")
end

local function open_in_browser(path)
	local opener
	if vim.fn.has("macunix") == 1 then
		opener = "open"
	elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
		opener = "cmd"
	else
		opener = "xdg-open"
	end
	if vim.fn.executable(opener) ~= 1 then
		return false
	end
	if opener == "cmd" then
		return vim.fn.jobstart({ "cmd", "/c", "start", "", path }, { detach = true }) > 0
	end
	return vim.fn.jobstart({ opener, path }, { detach = true }) > 0
end

local function handler(args)
	if not args.path or args.path == "" then
		return encode_checked(encode_json({ error = "path is required" }))
	end

	local abs_path, lookup_error = shared.resolve_note_or_error(args.path)
	if not abs_path then
		return encode_checked(encode_json(lookup_error))
	end

	local content = shared.read_content(abs_path)
	if not content then
		return encode_checked(encode_json({ error = "failed to read note: " .. abs_path }))
	end

	local metadata, body = require("notes.parser").parse(content, abs_path)
	if not metadata then
		return encode_checked(encode_json({ error = "failed to parse note: " .. args.path }))
	end

	local title = metadata.title
	if not title or title == "" then
		title = vim.fn.fnamemodify(abs_path, ":t:r")
	end
	local note_dir = vim.fn.fnamemodify(abs_path, ":h")

	local rendered = render_with_pandoc(body or "", note_dir)
	local engine = "pandoc"
	if not rendered then
		rendered = render_markdown(body or "", note_dir)
		engine = "builtin"
	end

	local output = args.output
	if not output or output == "" then
		local rel = shared.relative_path(abs_path) or vim.fn.fnamemodify(abs_path, ":t")
		output = shared.notes_dir .. "/.exports/" .. (rel:gsub("%.md$", "")) .. ".html"
	elseif output:sub(1, 1) ~= "/" then
		output = shared.notes_dir .. "/" .. output
	end
	output = vim.fn.fnamemodify(output, ":p")

	vim.fn.mkdir(vim.fn.fnamemodify(output, ":h"), "p")
	local f, err = io.open(output, "w")
	if not f then
		return encode_checked(encode_json({ error = "failed to write HTML: " .. tostring(err) }))
	end
	f:write(html_document(title, metadata, rendered))
	f:close()

	local opened = false
	if args.open then
		opened = open_in_browser(output)
	end

	return encode_checked(encode_json({
		success = true,
		path = output,
		relative_path = shared.relative_path(output),
		url = file_url(output),
		engine = engine,
		title = title,
		opened = opened or nil,
	}))
end

return {
	name = "notes_export_html",
	description = "Render one note to a standalone HTML file with inline CSS, returning an absolute path and a `file://` URL. Pandoc is optional: when installed it renders full Markdown (tables, task lists); otherwise a built-in renderer handles headings, lists/checkboxes, code, quotes, links, images, and wiki-links. Markdown links/images are sanitized, wiki-links render as styled labels, and local images resolve to absolute file URLs. `open=true` launches the system browser via `xdg-open`/`open`/`cmd`; if no opener exists the path and URL are still returned. `output` overrides the default path under `notes_dir/.exports/`.",
	inputSchema = {
		type = "object",
		properties = {
			path = { type = "string", description = "Note path, filename, or title (relative or absolute)" },
			output = {
				type = "string",
				description = "Optional output HTML path; relative paths resolve against notes_dir. Defaults to notes_dir/.exports/<note>.html",
			},
			open = {
				type = "boolean",
				description = "Open the generated file with the system opener (xdg-open/open/cmd); if unavailable, path and url are still returned",
			},
		},
		required = { "path" },
	},
	handler = handler,
}
