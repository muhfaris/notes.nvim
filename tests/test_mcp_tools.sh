#!/usr/bin/env bash
# Functional tests for the MCP tools added/changed alongside notes_backlinks'
# subtask-link matching fix: notes_tasks, notes_toggle_task, notes_add_subtask,
# notes_board_status, notes_rollover_tasks, notes_history, notes_diff.
#
# Runs against an isolated temp notes directory (NOTES_DIR) — never touches
# the caller's real vault. test_mcp.sh covers MCP protocol/schema shape; this
# covers tool behavior.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
notes_dir=$(mktemp -d)
state_dir=$(mktemp -d)
stderr_file=$(mktemp)
trap 'rm -rf "$notes_dir" "$state_dir" "$stderr_file"' EXIT

git -C "$notes_dir" init -q
git -C "$notes_dir" config user.email "test@example.com"
git -C "$notes_dir" config user.name "test"

pass=0
fail=0

check() {
	local desc="$1" cond="$2"
	if [ "$cond" = "true" ]; then
		pass=$((pass + 1))
		printf 'ok - %s\n' "$desc"
	else
		fail=$((fail + 1))
		printf 'FAIL - %s\n' "$desc"
	fi
}

# Send one tools/call request, return the tool's inner JSON result as text.
call() {
	local params_json="$1"
	printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":$params_json}" |
		NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
			--cmd "set runtimepath+=$repo_dir" \
			-c "lua require('notes.mcp').start()" 2>"$stderr_file" |
		jq -r '.result.content[0].text'
}

write_board() {
	cat >"$notes_dir/board.md" <<'EOF'
---
title: "Board"
date: "2026-09-15"
tags: []
summary: ""
---
# Board

### Monday
- [x] Category A
  - [x] done child

### Tuesday
- [ ] Category B
  - [ ] open child one
  - [x] finished child
EOF
}

git_commit_all() {
	git -C "$notes_dir" add -A
	git -C "$notes_dir" commit -q -m "$1" --allow-empty
}

write_board
git_commit_all "seed board"

# ── notes_tasks ──────────────────────────────────────────────────────────

out=$(call '{"name":"notes_tasks","arguments":{"status":"todo"}}')
check "notes_tasks: counts only todo checklist items" "$(echo "$out" | jq -e '.count == 2' >/dev/null && echo true || echo false)"

# ── inline TODO/ASK marker anchoring (start-of-line or end-of-line only) ──

cat >"$notes_dir/markers.md" <<'EOF'
---
title: "Markers"
date: "2026-09-15"
tags: []
summary: ""
---
- TODO: fix the thing
fix the other thing :todo
- ASK: confirm status
confirm the other status :ask
with todo sign, this is just prose
As an interviewer, I'd ask: a question
MASK: not a real ask marker
EOF

out=$(call '{"name":"notes_tasks","arguments":{"type":"todo"}}')
check "notes_tasks: catches 'TODO:' prefix and ':todo' suffix forms" "$(echo "$out" | jq -e '[.tasks[].text] | sort == ["fix the other thing","fix the thing"]' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_tasks","arguments":{"type":"ask"}}')
check "notes_tasks: catches 'ASK:' prefix and ':ask' suffix forms, rejects prose/word-internal matches" "$(echo "$out" | jq -e '[.tasks[].text] | sort == ["confirm status","confirm the other status"]' >/dev/null && echo true || echo false)"

rm -f "$notes_dir/markers.md"

# ── notes_board_status ───────────────────────────────────────────────────

out=$(call '{"name":"notes_board_status","arguments":{"path":"board.md"}}')
check "notes_board_status: totals across the note" "$(echo "$out" | jq -e '.totals == {"todo":2,"doing":0,"waiting":0,"done":3}' >/dev/null && echo true || echo false)"
check "notes_board_status: Tuesday section breakdown" "$(echo "$out" | jq -e '[.sections[] | select(.heading=="Tuesday")][0] == {"heading":"Tuesday","todo":2,"doing":0,"waiting":0,"done":1,"total":3}' >/dev/null && echo true || echo false)"

# ── notes_backlinks: subtask parent/child convention ────────────────────

mkdir -p "$notes_dir/tasks"
cat >"$notes_dir/tasks/child.md" <<'EOF'
---
title: "Child Task"
date: "2026-09-15"
tags: ["task"]
summary: ""
---
# Child Task
EOF
cat >"$notes_dir/linker.md" <<'EOF'
---
title: "Linker"
date: "2026-09-15"
tags: []
summary: ""
---
- [ ] Parent [[ Parent/Child Task]]
EOF
cat >"$notes_dir/linker_aliased.md" <<'EOF'
---
title: "Linker Aliased"
date: "2026-09-15"
tags: []
summary: ""
---
- [ ] [[ Parent/Child Task|Child Task]]
EOF

out=$(call '{"name":"notes_backlinks","arguments":{"path":"tasks/child.md"}}')
check "notes_backlinks: finds subtask-style parent/child link" "$(echo "$out" | jq -e '.count == 2 and ([.backlinks[].title] | sort) == ["Linker","Linker Aliased"]' >/dev/null && echo true || echo false)"

rm -f "$notes_dir/tasks/child.md" "$notes_dir/linker.md" "$notes_dir/linker_aliased.md"

# ── subtask titles containing "/" must not break link resolution ────────
# A naive last-"/"-segment split misreads "Category B/Fix A/B testing bug"
# as child title "B testing bug" instead of the real "Fix A/B testing bug".

write_board
out=$(call '{"name":"notes_add_subtask","arguments":{"path":"board.md","parent_match":"Category B","title":"Fix A/B testing bug"}}')
slash_detail=$(echo "$out" | jq -r '.detail_note')
check "notes_add_subtask: a title containing '/' still resolves its own detail link" "$([ -n \"$slash_detail\" ] && [ \"$slash_detail\" != \"null\" ] && echo true || echo false)"

out=$(call '{"name":"notes_tasks","arguments":{}}')
check "notes_tasks: detail resolves correctly when the title contains '/'" "$(echo "$out" | jq -e --arg d "$slash_detail" '[.tasks[] | select(.text == "Fix A/B testing bug")][0].detail == $d' >/dev/null && echo true || echo false)"

# ── subtask titles containing '"' must survive the frontmatter round-trip ──
# Frontmatter writers escape an embedded quote as `\"`; the parser must undo
# exactly that, or the detail note's title reads back as `Fix \"quoted\"
# thing`, which breaks both detail-link resolution and backlink matching.

write_board
out=$(call '{"name":"notes_add_subtask","arguments":{"path":"board.md","parent_match":"Category B","title":"Fix \"quoted\" thing"}}')
quote_detail=$(echo "$out" | jq -r '.detail_note')
check "notes_add_subtask: a title containing '\"' is written to its own detail note" "$([ -f "$quote_detail" ] && echo true || echo false)"
check "notes_add_subtask: quoted title renders as an un-aliased wikilink" "$(echo "$out" | jq -e '.line == "  - [ ] [[ Category B/Fix \"quoted\" thing ]]"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_tasks","arguments":{}}')
check "notes_tasks: detail resolves when the title contains '\"'" "$(echo "$out" | jq -e --arg d "$quote_detail" '[.tasks[] | select(.text == "Fix \"quoted\" thing")][0].detail == $d' >/dev/null && echo true || echo false)"

out=$(call "{\"name\":\"notes_backlinks\",\"arguments\":{\"path\":\"$quote_detail\"}}")
check "notes_backlinks: quoted title round-trips out of frontmatter unescaped" "$(echo "$out" | jq -e '.target.title == "Fix \"quoted\" thing" and .count >= 1' >/dev/null && echo true || echo false)"

# ── notes_add_subtask + notes_toggle_task (with detail-note sync) ───────

# ── alias (`[[ parent/child|label ]]`) is a supported alternative ───────
# An author-written alias is not a legacy format: the line must still resolve to
# its detail note *and* keep the label the author chose, instead of having it
# overwritten by the resolved detail note's own title.

write_board
out=$(call '{"name":"notes_add_subtask","arguments":{"path":"board.md","parent_match":"Category B","title":"aliased child"}}')
alias_target=$(echo "$out" | jq -r '.detail_note')
printf -- '- [ ] [[ Category B/aliased child|Short label ]]\n' >>"$notes_dir/board.md"

out=$(call '{"name":"notes_tasks","arguments":{"status":"todo"}}')
check "notes_tasks: an aliased line resolves to its detail note" "$(echo "$out" | jq -e --arg d "$alias_target" '[.tasks[] | select(.text == "Short label")][0].detail == $d' >/dev/null && echo true || echo false)"
check "notes_tasks: an aliased line keeps its own label, not the resolved title" "$(echo "$out" | jq -e '[.tasks[] | select(.text == "aliased child")] | length == 1' >/dev/null && echo true || echo false)"

# ── '*' bullets are checkbox lines too ───────────────────────────────
# The detail link used to be resolved behind a literal `- [` test -- false for
# `* [ ]` lines, even though the scanner itself accepts `[-*]` bullets.

write_board
out=$(call '{"name":"notes_add_subtask","arguments":{"path":"board.md","parent_match":"Category B","title":"star child"}}')
star_target=$(echo "$out" | jq -r '.detail_note')
printf -- '* [ ] [[ Category B/star child ]]\n' >>"$notes_dir/board.md"

out=$(call '{"name":"notes_tasks","arguments":{"status":"todo"}}')
# Two lines point at that detail note: the nested `- [ ]` line notes_add_subtask
# generated, and the hand-written `* [ ]` one. Before the fix the `*` line
# silently resolved nothing, so the count was 1.
check "notes_tasks: a '*' bullet resolves the same detail link as its '-' sibling" "$(echo "$out" | jq -e --arg d "$star_target" '[.tasks[] | select(.detail == $d)] | length == 2' >/dev/null && echo true || echo false)"

write_board
out=$(call '{"name":"notes_add_subtask","arguments":{"path":"board.md","parent_match":"Category B","title":"new subtask"}}')
check "notes_add_subtask: reports success" "$(echo "$out" | jq -e '.success == true' >/dev/null && echo true || echo false)"
detail_note=$(echo "$out" | jq -r '.detail_note')
check "notes_add_subtask: detail note was written to disk" "$([ -f "$detail_note" ] && echo true || echo false)"
check "notes_add_subtask: inserted line is a single un-aliased wikilink, no duplicated title" "$(echo "$out" | jq -e '.line == "  - [ ] [[ Category B/new subtask ]]"' >/dev/null && echo true || echo false)"
check "notes_add_subtask: detail note frontmatter has the parent" "$(grep -q 'parent: "\[\[ Category B \]\]"' "$detail_note" && echo true || echo false)"

out=$(call '{"name":"notes_tasks","arguments":{"status":"todo"}}')
check "notes_tasks: display text for a linked task is clean, not raw wikilink syntax" "$(echo "$out" | jq -e '[.tasks[] | select(.detail != null)][0].text == "new subtask"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","match":"new subtask","status":"doing"}}')
check "notes_toggle_task: flips the checkbox to doing" "$(echo "$out" | jq -e '.line == "  - [/] [[ Category B/new subtask ]]"' >/dev/null && echo true || echo false)"
check "notes_toggle_task: syncs the linked detail note's status" "$(echo "$out" | jq -e '.detail_synced == true' >/dev/null && echo true || echo false)"
check "notes_toggle_task: detail note frontmatter now has status: doing" "$(grep -q 'status: "doing"' "$detail_note" && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","match":"new subtask","status":"waiting"}}')
check "notes_toggle_task: flips the checkbox to waiting" "$(echo "$out" | jq -e '.line == "  - [?] [[ Category B/new subtask ]]"' >/dev/null && echo true || echo false)"
check "notes_toggle_task: stamps the detail note's status as waiting" "$(grep -q 'status: \"waiting\"' "$detail_note" && echo true || echo false)"

# The same line, read back through the scanner: a waiting task is still open.
out=$(call '{"name":"notes_tasks","arguments":{"type":"task","status":"waiting"}}')
check "notes_tasks: a waiting task is listed under status=waiting" "$(echo "$out" | jq -e '[.tasks[] | select(.text == "new subtask")] | length == 1' >/dev/null && echo true || echo false)"
check "notes_tasks: waiting is not a done task" "$(echo "$out" | jq -e '[.tasks[] | select(.status == "done")] | length == 0' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","match":"new subtask","status":"doing"}}')
check "notes_toggle_task: waiting -> doing" "$(echo "$out" | jq -e '.line == "  - [/] [[ Category B/new subtask ]]"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","match":"new subtask","status":"nope"}}')
check "notes_toggle_task: an unknown status is refused, and 'waiting' is named" "$(echo "$out" | jq -e '.error | test("waiting")' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_board_status","arguments":{"path":"board.md"}}')
check "notes_board_status: totals carry the waiting bucket" "$(echo "$out" | jq -e '.totals | has("waiting")' >/dev/null && echo true || echo false)"
check "notes_board_status: a section row carries the waiting bucket" "$(echo "$out" | jq -e '.sections[0] | has("waiting")' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","match":"child","status":"done"}}')
check "notes_toggle_task: ambiguous match is rejected with candidates" "$(echo "$out" | jq -e '.error and (.candidates | length) > 1' >/dev/null && echo true || echo false)"

# ── notes_rollover_tasks ─────────────────────────────────────────────────

write_board
out=$(call '{"name":"notes_rollover_tasks","arguments":{"from_path":"board.md","title":"Board W2"}}')
check "notes_rollover_tasks: reports success and a carried count" "$(echo "$out" | jq -e '.success == true and .carried_count == 3' >/dev/null && echo true || echo false)"
new_path=$(echo "$out" | jq -r '.path')
check "notes_rollover_tasks: created note exists" "$([ -f "$new_path" ] && echo true || echo false)"
check "notes_rollover_tasks: drops the fully-done Monday section" "$(! grep -q 'Monday' "$new_path" && echo true || echo false)"
check "notes_rollover_tasks: keeps the still-open Tuesday section" "$(grep -q 'Tuesday' "$new_path" && echo true || echo false)"
check "notes_rollover_tasks: drops the already-done sibling child" "$(! grep -q 'finished child' "$new_path" && echo true || echo false)"
check "notes_rollover_tasks: keeps the still-open child" "$(grep -q 'open child one' "$new_path" && echo true || echo false)"
check "notes_rollover_tasks: does not duplicate the source note's own H1 title" "$(! grep -qx '# Board' "$new_path" && echo true || echo false)"

# ── notes_history / notes_diff ───────────────────────────────────────────

git_commit_all "post-fixture changes"

out=$(call '{"name":"notes_history","arguments":{}}')
check "notes_history: vault-wide history does not error on --follow" "$(echo "$out" | jq -e '.error == null and .count >= 1' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_history","arguments":{"path":"board.md"}}')
check "notes_history: path-scoped history resolves the relative path" "$(echo "$out" | jq -e '.path == "board.md" and .count >= 1' >/dev/null && echo true || echo false)"

commit_hash=$(git -C "$notes_dir" log -1 --format=%H)
out=$(call "{\"name\":\"notes_diff\",\"arguments\":{\"commit\":\"$commit_hash\"}}")
check "notes_diff: returns a non-empty diff for a known commit" "$(echo "$out" | jq -e '.diff | length > 0' >/dev/null && echo true || echo false)"

# Not-a-repo path: a NOTES_DIR with no .git at all.
no_repo_dir=$(mktemp -d)
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"notes_history","arguments":{}}}' |
	NOTES_DIR="$no_repo_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
		--cmd "set runtimepath+=$repo_dir" \
		-c "lua require('notes.mcp').start()" 2>"$stderr_file" |
	jq -r '.result.content[0].text')
check "notes_history: clear error when notes dir is not a git repo" "$(echo "$out" | jq -e '.error != null' >/dev/null && echo true || echo false)"
rm -rf "$no_repo_dir"

# ── notes_search_content: Lua fallback path (rg/grep unavailable) ────────
# Forces the fallback by faking both executables as missing, and uses a
# query containing Lua pattern-magic characters ('.') to catch the
# vim.pesc()-plus-plain=true regression (pesc'ing a string then searching
# for it in plain mode makes the escape characters literal, so it can never
# match real content).

cat >"$notes_dir/needle.md" <<'EOF'
---
title: "Needle"
date: "2026-09-15"
tags: []
summary: ""
---
See v1.2.3 release notes and the project-alpha service for details.
EOF

out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"notes_search_content","arguments":{"query":"v1.2.3"}}}' |
	NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
		--cmd "set runtimepath+=$repo_dir" \
		-c "lua vim.fn.executable = function(_) return 0 end" \
		-c "lua require('notes.mcp').start()" 2>"$stderr_file" |
	jq -r '.result.content[0].text')
check "notes_search_content: Lua fallback finds a query containing pattern-magic characters" "$(echo "$out" | jq -e 'length == 1 and .[0].relative_path == "needle.md"' >/dev/null && echo true || echo false)"

rm -f "$notes_dir/needle.md"

# ── Path resolution by filename/title + suggestions ────────────────────────

mkdir -p "$notes_dir/documents/project-alpha/Y-m/weekly"
cat >"$notes_dir/documents/project-alpha/Y-m/weekly/w2-oct-2026.md" <<'EOF'
---
title: "Weekly: w2 oct 2026"
date: "2026-10-12"
tags: ["weekly"]
summary: ""
---
# Weekly: w2 oct 2026

- [ ] nested task
EOF

out=$(call '{"name":"notes_read","arguments":{"path":"w2-oct-2026.md"}}')
check "notes_read: a bare filename resolves anywhere in the vault" \
	"$(echo "$out" | jq -e '.relative_path == "documents/project-alpha/Y-m/weekly/w2-oct-2026.md" and .title == "Weekly: w2 oct 2026"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_read","arguments":{"path":"Weekly: w2 oct 2026"}}')
check "notes_read: a title resolves to its note" \
	"$(echo "$out" | jq -e '.relative_path == "documents/project-alpha/Y-m/weekly/w2-oct-2026.md"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_read","arguments":{"path":"w2-oct-2027.md"}}')
check "notes_read: a miss returns similar paths" \
	"$(echo "$out" | jq -e '.error != null and ([.suggestions[].relative_path] | index("documents/project-alpha/Y-m/weekly/w2-oct-2026.md")) != null' >/dev/null && echo true || echo false)"

# ── notes_resolve_link ────────────────────────────────────────────────────

mkdir -p "$notes_dir/tasks/2026/10"
cat >"$notes_dir/tasks/2026/10/2026-10-05-tag-status.md" <<'EOF'
---
title: "Tag status w2"
date: "2026-10-05"
tags: ["task"]
summary: ""
parent: "[[ Example Workstream ]]"
source_note: "documents/project-alpha/Y-m/weekly/w2-oct-2026.md"
---
# Tag status w2

- [ ] check the tag status
EOF

out=$(call '{"name":"notes_resolve_link","arguments":{"link":"[[ Example Workstream/Tag status w2 ]]"}}')
check "notes_resolve_link: resolves a Parent/Child link to the detail note" \
	"$(echo "$out" | jq -e '.relative_path == "tasks/2026/10/2026-10-05-tag-status.md" and .match != null' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_resolve_link","arguments":{"link":"[[ Example Workstream/Tag status w2x ]]"}}')
check "notes_resolve_link: an unresolved link returns suggestions" \
	"$(echo "$out" | jq -e '.error != null and (.suggestions | length) > 0' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_get_metadata","arguments":{"path":"2026-10-05-tag-status.md"}}')
check "notes_get_metadata: custom parent/source_note fields are returned" \
	"$(echo "$out" | jq -e '.parent == "[[ Example Workstream ]]" and .source_note == "documents/project-alpha/Y-m/weekly/w2-oct-2026.md"' >/dev/null && echo true || echo false)"

# ── notes_add_task: insert under a day and a parent ───────────────────────

write_board
out=$(call '{"name":"notes_add_task","arguments":{"path":"board.md","heading":"Tuesday","text":"new inline task","status":"doing"}}')
new_lnum=$(echo "$out" | jq -r '.lnum')
check "notes_add_task: inserts under the day heading with the requested status" \
	"$(echo "$out" | jq -e '.line == "- [/] new inline task"' >/dev/null && sed -n "${new_lnum}p" "$notes_dir/board.md" | grep -qxF -- '- [/] new inline task' && echo true || echo false)"

out=$(call '{"name":"notes_add_task","arguments":{"path":"board.md","heading":"Tuesday","parent":"Category B","link":"Category B/linked task"}}')
check "notes_add_task: nests a linked task under a parent" \
	"$(echo "$out" | jq -e '.line == "  - [ ] [[ Category B/linked task ]]"' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_toggle_task","arguments":{"path":"board.md","link":"[[ Category B/linked task ]]","mark":"x"}}')
check "notes_toggle_task: link + raw mark work as set_status(link, mark)" \
	"$(echo "$out" | jq -e '.line == "  - [x] [[ Category B/linked task ]]" and .status == "done"' >/dev/null && echo true || echo false)"

# ── notes_copy_task_to_today ──────────────────────────────────────────────

copy_date="2026-10-18"
out=$(call "{\"name\":\"notes_copy_task_to_today\",\"arguments\":{\"from_path\":\"board.md\",\"link\":\"Category B/linked task\",\"date\":\"$copy_date\"}}")
copy_target=$(echo "$out" | jq -r '.target_path // empty')
check "notes_copy_task_to_today: creates today's daily note" \
	"$(echo "$out" | jq -e '.target_created == true' >/dev/null && [ -f "$copy_target" ] && echo true || echo false)"
check "notes_copy_task_to_today: resets the copied box to todo, keeps the link, and keeps the parent group" \
	"$(echo "$out" | jq -e '.line == "  - [ ] [[ Category B/linked task ]]" and .parent == "Category B" and .parent_created == true' >/dev/null && grep -qF -- '  - [ ] [[ Category B/linked task ]]' "$copy_target" && grep -qxF -- '- [ ] Category B' "$copy_target" && echo true || echo false)"

out=$(call "{\"name\":\"notes_copy_task_to_today\",\"arguments\":{\"from_path\":\"board.md\",\"link\":\"Category B/linked task\",\"date\":\"$copy_date\"}}")
check "notes_copy_task_to_today: a second copy is deduplicated" \
	"$(echo "$out" | jq -e '.copied == false and .duplicate == true' >/dev/null && echo true || echo false)"

# ── notes_append_info ─────────────────────────────────────────────────────

cat >"$notes_dir/tasks/2026/10/2026-10-18-info-target.md" <<'EOF'
---
title: "Info Target"
date: "2026-10-18"
tags: ["task"]
summary: ""
---
# Info Target

## Summary

Some context.

- [ ] checklist one
EOF

out=$(call '{"name":"notes_append_info","arguments":{"path":"info-target","text":"shipped the fix","label":"Monday"}}')
info_lnum=$(echo "$out" | jq -r '.lnum')
check "notes_append_info: inserts the Info line directly above the checklist" \
	"$(echo "$out" | jq -e '.lines[0] == "- Info (Monday): shipped the fix"' >/dev/null && sed -n "${info_lnum}p" "$notes_dir/tasks/2026/10/2026-10-18-info-target.md" | grep -qx -- '- Info (Monday): shipped the fix' && echo true || echo false)"
check "notes_append_info: the checklist remains immediately after it" \
	"$(sed -n "$((info_lnum + 1))p" "$notes_dir/tasks/2026/10/2026-10-18-info-target.md" | grep -qxF -- '- [ ] checklist one' && echo true || echo false)"

# position='summary' must stay inside Summary, above its checklist, instead of
# drifting to the section end and touching the next heading.
cat >"$notes_dir/summary-position.md" <<'EOF'
---
title: "Summary Position"
date: "2026-10-18"
tags: []
summary: ""
---
# Summary Position

## Summary

Some context.

- [ ] checklist one
- [x] Konfirmasi ke QA ...

## Evidence

evidence text
EOF

out=$(call '{"name":"notes_append_info","arguments":{"path":"summary-position.md","text":"summary stays above the checklist","label":"Sun","position":"summary"}}')
summary_lnum=$(echo "$out" | jq -r '.lnum')
checklist_lnum=$(grep -nxF -- '- [ ] checklist one' "$notes_dir/summary-position.md" | cut -d: -f1)
evidence_lnum=$(grep -nxF -- '## Evidence' "$notes_dir/summary-position.md" | cut -d: -f1)
check "notes_append_info position=summary: lands above the Summary checklist" \
	"$([ "$summary_lnum" -lt "$checklist_lnum" ] && echo true || echo false)"
check "notes_append_info position=summary: does not drift below the checklist" \
	"$([ "$summary_lnum" -lt "$evidence_lnum" ] && sed -n "$((evidence_lnum - 1))p" "$notes_dir/summary-position.md" | grep -q '^$' && echo true || echo false)"

cat >"$notes_dir/summary-prose.md" <<'EOF'
---
title: "Summary Prose"
date: "2026-10-18"
tags: []
summary: ""
---
# Summary Prose

## Summary

Some context.

## Evidence

evidence text
EOF

out=$(call '{"name":"notes_append_info","arguments":{"path":"summary-prose.md","text":"after the prose","label":"Sun","position":"summary"}}')
prose_info_lnum=$(echo "$out" | jq -r '.lnum')
prose_evidence_lnum=$(grep -nxF -- '## Evidence' "$notes_dir/summary-prose.md" | cut -d: -f1)
check "notes_append_info position=summary: a prose-only section keeps a blank line before the next heading" \
	"$(sed -n "$((prose_evidence_lnum - 1))p" "$notes_dir/summary-prose.md" | grep -q '^$' && [ "$prose_info_lnum" -lt "$prose_evidence_lnum" ] && echo true || echo false)"

# ── expected_hash rejects concurrent edits ────────────────────────────────

out=$(call '{"name":"notes_read","arguments":{"path":"board.md"}}')
old_hash=$(echo "$out" | jq -r '.hash')
printf '\n- [ ] concurrent edit\n' >>"$notes_dir/board.md"

out=$(call "{\"name\":\"notes_update\",\"arguments\":{\"path\":\"board.md\",\"summary\":\"should not apply\",\"expected_hash\":\"$old_hash\"}}")
check "notes_update: a stale expected_hash is refused" \
	"$(echo "$out" | jq -e '.code == "stale_note" and .current_hash != .expected_hash' >/dev/null && echo true || echo false)"
check "notes_update: the stale write did not touch the file" \
	"$(! grep -q 'should not apply' "$notes_dir/board.md" && echo true || echo false)"

# ── notes_create: task-detail convention + board insertion ────────────────

cat >"$notes_dir/create_board.md" <<'EOF'
---
title: "Create Board"
date: "2026-10-18"
tags: []
summary: ""
---
# Create Board

### Wednesday
- [ ] Category B
EOF

out=$(call '{"name":"notes_create","arguments":{"title":"Created Child","parent":"Category B","source_note":"documents/project-alpha/Y-m/weekly/w2-oct-2026.md","date":"2026-10-18","board_path":"create_board.md","heading":"Wednesday"}}')
created_path=$(echo "$out" | jq -r '.path')
check "notes_create: parent uses the tasks/YYYY/MM/date-slug path convention" \
	"$(echo "$out" | jq -e '.relative_path == "tasks/2026/10/2026-10-18-created-child.md"' >/dev/null && [ -f "$created_path" ] && echo true || echo false)"
check "notes_create: task frontmatter carries parent and source_note" \
	"$(grep -q 'parent: "\[\[ Category B \]\]"' "$created_path" && grep -q 'source_note: "documents/project-alpha/Y-m/weekly/w2-oct-2026.md"' "$created_path" && echo true || echo false)"
check "notes_create: board line is inserted under the parent" \
	"$(echo "$out" | jq -e '.board_line == "  - [ ] [[ Category B/Created Child ]]"' >/dev/null && grep -qF -- '  - [ ] [[ Category B/Created Child ]]' "$notes_dir/create_board.md" && echo true || echo false)"

# ── copy between day sections of the same board ───────────────────────────

cat >"$notes_dir/copy_days.md" <<'EOF'
---
title: "Copy Days"
date: "2026-10-18"
tags: []
summary: ""
---
# Copy Days

## Saturday
- [ ] Same task

## Sunday
- [ ] Other task
EOF

out=$(call '{"name":"notes_copy_task_to_today","arguments":{"from_path":"copy_days.md","heading":"Saturday","match":"Same task","target_path":"copy_days.md","target_heading":"Sunday"}}')
check "notes_copy_task_to_today: copies between two headings of the same board" \
	"$(echo "$out" | jq -e '.copied == true and .target_heading == "Sunday"' >/dev/null && [ "$(grep -cF -- '- [ ] Same task' "$notes_dir/copy_days.md")" = "2" ] && echo true || echo false)"
sunday_lnum=$(grep -nxF -- '## Sunday' "$notes_dir/copy_days.md" | cut -d: -f1)
copied_lnum=$(grep -nF -- '- [ ] Same task' "$notes_dir/copy_days.md" | tail -1 | cut -d: -f1)
check "notes_copy_task_to_today: the copy lands under the destination heading" \
	"$([ "$copied_lnum" -gt "$sunday_lnum" ] && echo true || echo false)"

out=$(call '{"name":"notes_copy_task_to_today","arguments":{"from_path":"copy_days.md","heading":"Saturday","match":"Same task","target_path":"copy_days.md","target_heading":"Sunday"}}')
check "notes_copy_task_to_today: duplicate detection is scoped to the destination heading" \
	"$(echo "$out" | jq -e '.copied == false and .duplicate == true' >/dev/null && [ "$(grep -cF -- '- [ ] Same task' "$notes_dir/copy_days.md")" = "2" ] && echo true || echo false)"

# ── notes_create: content is used verbatim ────────────────────────────────

out=$(call '{"name":"notes_create","arguments":{"title":"Probe detail task","content":"# Probe detail task\n\nBody text."}}')
probe_path=$(echo "$out" | jq -r '.path')
check "notes_create: supplied content replaces the template skeleton" \
	"$([ "$(grep -c '^# Probe detail task$' "$probe_path")" = "1" ] && ! grep -q '^## Description$' "$probe_path" && grep -q '^Body text\.$' "$probe_path" && echo true || echo false)"
check "notes_create: default frontmatter date keeps the time component" \
	"$(echo "$out" | jq -e '.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$")' >/dev/null && echo true || echo false)"

out=$(call '{"name":"notes_create","arguments":{"title":"Probe child","parent":"Bug Finding","content":"# Probe child\n\nBody text."}}')
probe_child_path=$(echo "$out" | jq -r '.path')
check "notes_create: task content is not wrapped in an extra H1/## Notes" \
	"$([ "$(grep -c '^# Probe child$' "$probe_child_path")" = "1" ] && ! grep -q '^## Notes$' "$probe_child_path" && echo true || echo false)"

# ── notes_create: exact parent task beats child-link substring ────────────

cat >"$notes_dir/parent_board.md" <<'EOF'
---
title: "Parent Board"
date: "2026-10-18"
tags: []
summary: ""
---
# Parent Board

## Sunday
- [ ] Bug Finding
  - [ ] [[ Bug Finding/Investigate crash ]]
EOF

out=$(call '{"name":"notes_create","arguments":{"title":"Probe linked child","parent":"Bug Finding","board_path":"parent_board.md","heading":"Sunday"}}')
check "notes_create: an exact parent label wins over child links containing it" \
	"$(echo "$out" | jq -e '.board_error == null and .board_line == "  - [ ] [[ Bug Finding/Probe linked child ]]"' >/dev/null && echo true || echo false)"

# ── notes_append_info: existing Info lines stay contiguous ────────────────

cat >"$notes_dir/info-contiguous.md" <<'EOF'
---
title: "Info Contiguous"
date: "2026-10-18"
tags: []
summary: ""
---
# Info Contiguous

## Summary

- Info (Sat): created by probe.

- [ ] checklist one
EOF

out=$(call '{"name":"notes_append_info","arguments":{"path":"info-contiguous.md","text":"summary-mode probe","label":"Sun","position":"summary"}}')
sat_lnum=$(grep -nxF -- '- Info (Sat): created by probe.' "$notes_dir/info-contiguous.md" | cut -d: -f1)
sun_lnum=$(grep -nxF -- '- Info (Sun): summary-mode probe' "$notes_dir/info-contiguous.md" | cut -d: -f1)
check "notes_append_info position=summary: consecutive Info lines are not split by a blank line" \
	"$([ "$sun_lnum" = "$((sat_lnum + 1))" ] && echo true || echo false)"
check "notes_append_info position=summary: the checklist separator remains below the Info block" \
	"$(sed -n "$((sun_lnum + 1))p" "$notes_dir/info-contiguous.md" | grep -q '^$' && echo true || echo false)"

# ── copy preserves the parent group and consumes an empty placeholder ─────

cat >"$notes_dir/copy_parent.md" <<'EOF'
---
title: "Copy Parent"
date: "2026-10-18"
tags: []
summary: ""
---
# Copy Parent

## Saturday
- [/] Bug Finding
  - [/] [[ Bug Finding/Existing probe task ]]

## Sunday
- [ ]
- [ ] Other task
EOF

out=$(call '{"name":"notes_copy_task_to_today","arguments":{"from_path":"copy_parent.md","link":"[[ Bug Finding/Existing probe task ]]","target_path":"copy_parent.md","target_heading":"Sunday"}}')
check "notes_copy_task_to_today: recreates the missing parent group in the destination" \
	"$(echo "$out" | jq -e '.copied == true and .parent == "Bug Finding" and .parent_created == true and .placeholder_replaced == true' >/dev/null && echo true || echo false)"
check "notes_copy_task_to_today: the copied task is nested under the parent" \
	"$(echo "$out" | jq -e '.line == "  - [ ] [[ Bug Finding/Existing probe task ]]"' >/dev/null && grep -qxF -- '  - [ ] [[ Bug Finding/Existing probe task ]]' "$notes_dir/copy_parent.md" && echo true || echo false)"
check "notes_copy_task_to_today: the empty destination placeholder is consumed" \
	"$(! grep -qxF -- '- [ ]' "$notes_dir/copy_parent.md" && echo true || echo false)"

cat >"$notes_dir/copy_parent_reuse.md" <<'EOF'
---
title: "Copy Parent Reuse"
date: "2026-10-18"
tags: []
summary: ""
---
# Copy Parent Reuse

## Saturday
- [/] Bug Finding
  - [/] [[ Bug Finding/Second probe ]]

## Sunday
- [/] Bug Finding
  - [ ] existing child
- [ ]
EOF

out=$(call '{"name":"notes_copy_task_to_today","arguments":{"from_path":"copy_parent_reuse.md","link":"[[ Bug Finding/Second probe ]]","target_path":"copy_parent_reuse.md","target_heading":"Sunday"}}')
check "notes_copy_task_to_today: reuses an existing destination parent instead of creating another" \
	"$(echo "$out" | jq -e '.copied == true and .parent == "Bug Finding" and .parent_created == null' >/dev/null && [ "$(grep -cxF -- '- [/] Bug Finding' "$notes_dir/copy_parent_reuse.md")" = "2" ] && echo true || echo false)"
check "notes_copy_task_to_today: the reused parent gains the copied child" \
	"$(grep -qxF -- '  - [ ] [[ Bug Finding/Second probe ]]' "$notes_dir/copy_parent_reuse.md" && ! grep -qxF -- '- [ ]' "$notes_dir/copy_parent_reuse.md" && echo true || echo false)"

cat >"$notes_dir/copy_placeholder.md" <<'EOF'
---
title: "Copy Placeholder"
date: "2026-10-18"
tags: []
summary: ""
---
# Copy Placeholder

## Saturday
- [ ] Plain task

## Sunday
- [ ]
- [ ] Other task
EOF

out=$(call '{"name":"notes_copy_task_to_today","arguments":{"from_path":"copy_placeholder.md","match":"Plain task","target_path":"copy_placeholder.md","target_heading":"Sunday"}}')
check "notes_copy_task_to_today: an empty placeholder is replaced in place when there is no parent" \
	"$(echo "$out" | jq -e '.copied == true and .placeholder_replaced == true and .parent == null' >/dev/null && [ "$(grep -cxF -- '- [ ] Plain task' "$notes_dir/copy_placeholder.md")" = "2" ] && ! grep -qxF -- '- [ ]' "$notes_dir/copy_placeholder.md" && echo true || echo false)"
other_lnum=$(grep -nxF -- '- [ ] Other task' "$notes_dir/copy_placeholder.md" | cut -d: -f1)
copied_plain_lnum=$(grep -nF -- '- [ ] Plain task' "$notes_dir/copy_placeholder.md" | tail -1 | cut -d: -f1)
check "notes_copy_task_to_today: the replacement keeps the placeholder's position" \
	"$([ "$copied_plain_lnum" -lt "$other_lnum" ] && echo true || echo false)"

# ── notes_export_html ─────────────────────────────────────────────────────

cat >"$notes_dir/export-probe.md" <<'EOF'
---
title: "Export Probe"
date: "2026-10-18 12:00:00"
tags: ["probe"]
summary: ""
---
# Export Probe

- [ ] task one
- [x] task two

See [[ Example Workstream/Tag status w2 ]].

<script>alert(1)</script>
EOF

out=$(call '{"name":"notes_export_html","arguments":{"path":"export-probe.md","output":"exports/export-probe.html"}}')
export_path=$(echo "$out" | jq -r '.path')
check "notes_export_html: writes a standalone HTML file and returns a file URL" \
	"$(echo "$out" | jq -e '.success == true and (.engine == "pandoc" or .engine == "builtin") and (.url | startswith("file://"))' >/dev/null && [ -f "$export_path" ] && echo true || echo false)"
check "notes_export_html: renders headings and checklist text" \
	"$(grep -q '<h1' "$export_path" && grep -q 'task one' "$export_path" && echo true || echo false)"
check "notes_export_html: renders wiki-links as labels" \
	"$(grep -q 'wikilink' "$export_path" && grep -q 'Tag status w2' "$export_path" && echo true || echo false)"
check "notes_export_html: raw HTML in the note is escaped" \
	"$(! grep -q '<script>alert' "$export_path" && grep -q '&lt;script&gt;' "$export_path" && echo true || echo false)"

# Force the no-pandoc path so the built-in renderer is covered too.
out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"notes_export_html","arguments":{"path":"export-probe.md","output":"exports/export-probe-builtin.html"}}}' |
	NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
		--cmd "set runtimepath+=$repo_dir" \
		-c "lua vim.fn.executable = function(_) return 0 end" \
		-c "lua require('notes.mcp').start()" 2>"$stderr_file" |
	jq -r '.result.content[0].text')
builtin_path=$(echo "$out" | jq -r '.path')
check "notes_export_html: built-in fallback renders without pandoc" \
	"$(echo "$out" | jq -e '.success == true and .engine == "builtin"' >/dev/null && grep -q '<h1' "$builtin_path" && grep -q 'task one' "$builtin_path" && grep -q 'wikilink' "$builtin_path" && echo true || echo false)"

printf '\n%d / %d checks passed\n' "$pass" "$((pass + fail))"
if [ "$fail" -ne 0 ]; then
	exit 1
fi
