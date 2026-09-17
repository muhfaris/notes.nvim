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
check "notes_board_status: totals across the note" "$(echo "$out" | jq -e '.totals == {"todo":2,"doing":0,"done":3}' >/dev/null && echo true || echo false)"
check "notes_board_status: Tuesday section breakdown" "$(echo "$out" | jq -e '[.sections[] | select(.heading=="Tuesday")][0] == {"heading":"Tuesday","todo":2,"doing":0,"done":1,"total":3}' >/dev/null && echo true || echo false)"

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
See v1.2.3 release notes and the new-helpdesk service for details.
EOF

out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"notes_search_content","arguments":{"query":"v1.2.3"}}}' |
	NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
		--cmd "set runtimepath+=$repo_dir" \
		-c "lua vim.fn.executable = function(_) return 0 end" \
		-c "lua require('notes.mcp').start()" 2>"$stderr_file" |
	jq -r '.result.content[0].text')
check "notes_search_content: Lua fallback finds a query containing pattern-magic characters" "$(echo "$out" | jq -e 'length == 1 and .[0].relative_path == "needle.md"' >/dev/null && echo true || echo false)"

rm -f "$notes_dir/needle.md"

printf '\n%d / %d checks passed\n' "$pass" "$((pass + fail))"
if [ "$fail" -ne 0 ]; then
	exit 1
fi
