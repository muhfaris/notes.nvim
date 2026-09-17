-- Checks for the checklist-line grammar owned by notes.shared.tasks.
-- Run via tests/test_task_grammar.sh (needs Neovim: the grammar uses
-- vim.fn/vim.trim, so plain `lua` cannot load the module).

local checks, failures = 0, 0
local function check(ok, desc)
	checks = checks + 1
	if ok then
		print("ok - " .. desc)
	else
		failures = failures + 1
		print("FAIL - " .. desc)
	end
end

local tasks = require("notes.shared.tasks")

-- The dead identity map `M.statuses = { todo = "todo", doing = "doing" }` is
-- gone: it was never a box map, and nothing read it but its own definition.
check(tasks.statuses == nil, "M.statuses (the dead identity map) is removed")

-- parse_task_line: the one pattern. Captures the box instead of testing it.
local parsed = tasks.parse_task_line("  * [/] b [[ X/Y ]]")
check(parsed ~= nil, "parse_task_line accepts a '*' bullet with an indent")
check(parsed and parsed.indent == "  ", "parse_task_line captures the indent")
check(parsed and parsed.box == "/", "parse_task_line captures the box char")
check(parsed and parsed.rest == " b [[ X/Y ]]", "parse_task_line captures the rest, link included")
check(tasks.parse_task_line("plain text") == nil, "parse_task_line is nil off a checklist line")
check(tasks.parse_task_line("") == nil, "parse_task_line is nil on an empty line")

-- is_task_line: the strict gate. Known boxes pass, unclassifiable ones do not.
for _, line in ipairs({ "- [ ] a", "* [/] b", "  - [x] c", "- [~] d", "  * [X] e", "- [-] f" }) do
	check(tasks.is_task_line(line), "is_task_line accepts: " .. line)
end
for _, line in ipairs({ "- [!] e", "- [?] e", "# [ ] e", "- [] e", "plain text", "" }) do
	check(not tasks.is_task_line(line), "is_task_line rejects: " .. line)
end

-- box_status / status_box: one map, both directions.
check(tasks.box_status(" ") == "todo", "box ' ' reads as todo")
check(tasks.box_status("/") == "doing", "box '/' reads as doing")
check(tasks.box_status("~") == "doing", "box '~' reads as doing")
check(tasks.box_status("x") == "done", "box 'x' reads as done")
check(tasks.box_status("X") == "done", "box 'X' reads as done")
check(tasks.box_status("!") == nil, "an unrecognized box has no status")
check(tasks.box_status(nil) == nil, "a nil box has no status")
check(tasks.status_box("todo") == " " and tasks.status_box("doing") == "/" and tasks.status_box("done") == "x",
	"status_box is the inverse of box_status")
check(tasks.status_box("nope") == nil, "status_box is nil for an unknown status")

-- is_open_box: the open-task whitelist shared by the scanner and rollover.
check(tasks.is_open_box(" ") and tasks.is_open_box("/") and tasks.is_open_box("~"), "todo/doing boxes are open")
check(not tasks.is_open_box("x") and not tasks.is_open_box("X"), "done boxes are not open")
check(not tasks.is_open_box("!") and not tasks.is_open_box(nil), "an unrecognized box is not open")

-- set_box: rewrites the box and nothing else.
check(tasks.set_box("- [ ] a", "/") == "- [/] a", "set_box promotes todo to doing")
check(tasks.set_box("  * [x] b [[ X/Y ]]", " ") == "  * [ ] b [[ X/Y ]]", "set_box keeps the indent and the link")
check(tasks.set_box("- [ ] a [b]", "x") == "- [x] a [b]", "set_box ignores a later bracket pair")
check(tasks.set_box("no checkbox here", "x") == "no checkbox here", "set_box is a no-op off a checklist line")

-- Two documented widenings of the editor toggle, both making it agree with the
-- scanner: `[X]` is done (box_status says so; the old four-branch pattern only
-- knew lowercase x), and `-[ ]` with no space after the bullet is a list item.
check(tasks.is_task_line("-[ ] no space") and tasks.box_status("X") == "done", "the widenings are recognized")

-- display_task_text: the alias wins, else the link's last segment.
check(tasks.display_task_text(" [[ X/Y ]]") == "Y", "display falls back to the child segment")
check(tasks.display_task_text(" [[ X/Y|short ]]") == "short", "display keeps an author's alias")
check(tasks.display_task_text(" Plain title [[ X/Y ]]") == "Plain title", "display keeps plain text")

-- subtask.parent_from_line is the same reader: it must not drift from Home's
-- kanban label for the same line.
local subtask = require("notes.subtask")
check(subtask.parent_from_line("- [ ] [[ X/Y ]]") == "Y", "parent_from_line agrees with display (child segment)")
check(subtask.parent_from_line("- [ ] [[ X/Y|short ]]") == "short", "parent_from_line agrees with display (alias)")
check(subtask.parent_from_line("- [ ] Plain title [[ X/Y ]]") == "Plain title", "parent_from_line keeps plain text")
check(subtask.parent_from_line("- [ ] ") == nil, "parent_from_line is nil with nothing left")
check(subtask.is_task_line("- [ ] x") and not subtask.is_task_line("- [!] x"), "subtask.is_task_line delegates to the gate")

-- ── Scan level: the same grammar decides which boxes become cards ──────────
local notes_dir = vim.env.NOTES_DIR
local function write(rel, body)
	local path = notes_dir .. "/" .. rel
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local f = assert(io.open(path, "w"), "could not write " .. path)
	f:write(body)
	f:close()
end

write("Board.md", table.concat({
	"---",
	'title: "Board"',
	"---",
	"- [ ] open todo",
	"* [/] open doing",
	"  - [~] nested doing",
	"- [x] done, not a card",
	"- [X] done too",
	"- [!] unclassifiable, not a card",
	"- [ ] [[Board/Linked child]]",
	"",
}, "\n"))
write("Board/Linked child.md", "---\ntitle: \"Linked child\"\n---\n\n## Notes\n")

local found = {}
for _, t in ipairs(tasks.scan(notes_dir)) do
	found[t.text] = t
end

check(found["open todo"] ~= nil and found["open todo"].status == "todo", "scan: '- [ ]' becomes a todo card")
check(found["open doing"] ~= nil and found["open doing"].status == "doing", "scan: '[/]' becomes a doing card")
check(found["nested doing"] ~= nil and found["nested doing"].status == "doing", "scan: '[~]' becomes a doing card")
check(found["done, not a card"] == nil, "scan: '[x]' never becomes a card")
check(found["done too"] == nil, "scan: '[X]' never becomes a card")
check(found["unclassifiable, not a card"] == nil, "scan: an unrecognized box never becomes a card")
check(found["Linked child"] ~= nil and found["Linked child"].detail ~= nil, "scan: a link-only line resolves its detail note")

-- ── The editor toggle, through the same grammar ───────────────────────────
local editor_tasks = require("notes.tasks")
local function toggle(line)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
	editor_tasks.toggle_task()
	return vim.api.nvim_get_current_line()
end

check(toggle("- [ ] toggle me") == "- [x] toggle me", "toggle: todo -> done")
check(toggle("- [x] toggle me") == "- [ ] toggle me", "toggle: done -> todo")
check(toggle("- [X] toggle me") == "- [ ] toggle me", "toggle: '[X]' is done, so it toggles")
check(toggle("- [/] in progress") == "- [/] in progress", "toggle: an in-progress line is left alone")
check(toggle("plain text") == "plain text", "toggle: a non-task line is left alone")

print(string.format("\n%d / %d checks passed", checks - failures, checks))
if failures > 0 then
	vim.cmd("cquit!")
end
vim.cmd("qa!")
