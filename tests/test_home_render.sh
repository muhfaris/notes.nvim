#!/usr/bin/env bash
# Functional tests for the Notes Home dashboard render: the pinned watchlist
# cards, the Week block (headings + leaf detection), the lane scope, and the
# `w` waiting key's action target.
#
# Runs against an isolated temp notes directory (NOTES_DIR), an isolated MRU
# state (XDG_DATA_HOME) and an isolated state dir — never touches the caller's
# real vault.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
notes_dir=$(mktemp -d)
state_dir=$(mktemp -d)
data_dir=$(mktemp -d)
trap 'rm -rf "$notes_dir" "$state_dir" "$data_dir"' EXIT

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

mkdir -p "$notes_dir/tasks"

cat >"$notes_dir/board.md" <<'EOF'
---
title: "Weekly W3"
date: "2026-09-17"
tags: []
summary: ""
pinned: true
---

### Wednesday [[Daily Note: 2026-09-09]]

- [ ] Workstream
  - [ ] send the recap mail
  - [?] waiting on RM for the number
- [~] draft the migration plan
- [!] not a real box

### Thrusday

- [ ] review the PR
EOF

# A second note with open work that is NOT pinned: the lanes must not show it.
cat >"$notes_dir/other.md" <<'EOF'
---
title: "Unrelated Note"
date: "2026-09-16"
tags: []
summary: ""
---

- [ ] not in the pinned board
EOF

render_out=$(
	NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" XDG_DATA_HOME="$data_dir" \
		nvim --clean --headless -i NONE \
		--cmd "set runtimepath+=$repo_dir" \
		-c "lua local b=vim.api.nvim_create_buf(false,true); require('notes.home').render(b); io.write(table.concat(vim.api.nvim_buf_get_lines(b,0,-1,false),'\n')); io.write('\n@@ACTIONS@@\n'); io.write(vim.g.notes_home_actions)" \
		-c "qa!" 2>&1
)

has() { printf '%s' "$render_out" | grep -qF -- "$1" && echo true || echo false; }
hasnt() { printf '%s' "$render_out" | grep -qF -- "$1" && echo false || echo true; }

check "scope line counts 1 pinned / 5 open / 4 next" \
	"$(has 'scope: 1 pinned · 5 open · 4 next')"
check "scope line points at the vault-wide view" \
	"$(has 'vault-wide lives in `:Notes tasks`')"

check "pinned card shows live open/next counts" \
	"$(has '📌 Weekly W3   ·  5 open · 4 next')"
check "pinned card shows its next leaves" \
	"$(has '        ▸ send the recap mail')"

check "week block names its board" \
	"$(has '🗓  This Week — Weekly W3')"
check "week block keeps the board's own heading" \
	"$(has '   Wednesday')"
check "week block strips a heading's trailing wikilink" \
	"$(hasnt '[[Daily Note: 2026-09-09]]')"
check "week block shows a container's child inside its heading" \
	"$(has '     ▸ review the PR')"

check "an unrecognized box is never rendered" \
	"$(hasnt '[!] not a real box')"
check "an un-pinned note stays out of the lanes" \
	"$(hasnt 'not in the pinned board')"

check "lanes are scoped: in progress (1)" "$(has '🔁 In Progress (1)')"
check "lanes are scoped: todo (3)" "$(has '📝 Todo (3)')"
check "waiting gets its own lane" "$(has '⏳ Waiting on someone (1)')"
check "the waiting card renders with its glyph" \
	"$(has '         ⏳  waiting on RM for the number')"
check "empty lanes say so" "$(has '❓ Ask (0)')"

check "quick actions advertise the waiting key" "$(has '[w] waiting')"
check "a waiting card carries a target for the w key" \
	"$(has '"status":"waiting"')"

check "the MRU is isolated: no recent notes" "$(has '(no recent notes yet')"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
