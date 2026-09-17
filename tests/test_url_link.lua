-- Minimal self-check for markdown URL link detection.
-- Run with: lua tests/test_url_link.lua

local tests = 0
local passed = 0

local function check(ok, msg)
	tests = tests + 1
	if ok then
		passed = passed + 1
	else
		io.stderr:write("FAIL: " .. msg .. "\n")
	end
end

local function find_md_links(line)
	local links = {}
	local pos = 1
	while true do
		local s, e, text, url = line:find("%[([^%]]-)%]%(([^)]-)%)", pos)
		if not s then break end
		table.insert(links, { text = text, url = url, start = s, end_ = e })
		pos = e + 1
	end
	return links
end

local function extract_scheme(url)
	local trimmed = url:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return nil end
	return trimmed:match("^([a-zA-Z][a-zA-Z0-9+%-]*)://")
end

-- 1. Standard markdown link
local links = find_md_links("click [here](https://example.com) now")
check(#links == 1, "should find 1 link")
if #links > 0 then
	check(links[1].text == "here", "link text: 'here'")
	check(links[1].url == "https://example.com", "url: 'https://example.com'")
end

-- 2. Multiple links on one line
links = find_md_links("[a](url1) and [b](url2)")
check(#links == 2, "should find 2 links")
if #links > 1 then
	check(links[1].text == "a", "first text: 'a'")
	check(links[2].text == "b", "second text: 'b'")
	check(links[1].url == "url1", "first url")
	check(links[2].url == "url2", "second url")
end

-- 3. No link
links = find_md_links("just plain text with [bracket but no paren")
check(#links == 0, "no links found for plain text")

-- 4. URL with hyphens and slashes
links = find_md_links("[ticket](https://app.clickup.com/t/9018427820)")
check(#links == 1, "clickup url found")
if #links > 0 then
	check(links[1].url == "https://app.clickup.com/t/9018427820", "full clickup url")
end

-- 5. file:// protocol links
links = find_md_links("open [config](file:///home/user/.notes/config.lua)")
check(#links == 1, "file:// link found")
if #links > 0 then
	check(links[1].url == "file:///home/user/.notes/config.lua", "file url")
end

-- 6. Scheme extraction
check(extract_scheme("https://example.com") == "https", "scheme: https")
check(extract_scheme("file:///path") == "file", "scheme: file")
check(extract_scheme("") == nil, "empty url has no scheme")
check(extract_scheme("  ") == nil, "whitespace url has no scheme")

io.write(string.format("\n%d / %d checks passed\n", passed, tests))
if passed ~= tests then
	io.write("SOME CHECKS FAILED\n")
	os.exit(1)
else
	io.write("ALL CHECKS PASSED\n")
	os.exit(0)
end
