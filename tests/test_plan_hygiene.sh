#!/usr/bin/env bash
# Plan-doc hygiene: the plan convention is machine-checkable, so check it.
#
# `.codecompanion/plans/<status>/<slug>/plan.md` must open with bare
# `Status:`/`Date:`/`Scope:` lines, exactly once each, and `Status` must match
# the folder prefix — 0-active -> active, 1-done -> done, 2-archive -> archived.
#
# Why this is a test and not a note: plans are the record an agent reads
# *instead of* re-deriving state, so drift costs real tokens on the next task.
# A `Status: done` plan sitting in 0-active/ reads as open work; a plan that is
# a single `Status: done` line documents nothing; a duplicated `Status:` line
# makes "is this open?" ambiguous. All three had happened.
#
# Read-only. No Neovim, no notes dir.
set -uo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plans_dir="$repo_dir/.codecompanion/plans"

pass=0
fail=0

check() {
	local desc="$1" ok="$2"
	if [ "$ok" = "1" ]; then
		pass=$((pass + 1))
		printf 'ok - %s\n' "$desc"
	else
		fail=$((fail + 1))
		printf 'FAIL - %s\n' "$desc"
	fi
}

# Number of frontmatter-looking lines for a key. 0 for an absent key.
count_of() {
	grep -c "^$2:" "$1" 2>/dev/null || true
}

status_of() {
	sed -n 's/^Status:[[:space:]]*//p' "$1" | head -1
}

if [ ! -d "$plans_dir" ]; then
	printf 'SKIP - %s is local-only and absent\n' "$plans_dir"
	exit 0
fi

for dir in "$plans_dir"/*/*/; do
	[ -d "$dir" ] || continue
	slug_dir=${dir%/}
	name=${slug_dir#"$plans_dir"/}
	folder=${name%%/*}
	plan="$slug_dir/plan.md"

	if [ ! -f "$plan" ]; then
		check "$name has a plan.md" 0
		continue
	fi

	case "$folder" in
		0-active) want=active ;;
		1-done) want=done ;;
		2-archive) want=archived ;;
		*) want="" ;;
	esac

	check "$name: exactly one Status: line" "$([ "$(count_of "$plan" Status)" = "1" ] && echo 1 || echo 0)"

	got=$(status_of "$plan")
	check "$name: Status '$got' matches folder '$folder'" \
		"$([ -n "$want" ] && [ "$got" = "$want" ] && echo 1 || echo 0)"

	check "$name: has a Date:" "$([ "$(count_of "$plan" Date)" = "1" ] && echo 1 || echo 0)"
	check "$name: has a Scope:" "$([ "$(count_of "$plan" Scope)" = "1" ] && echo 1 || echo 0)"
	check "$name: frontmatter is not ---fenced" \
		"$([ "$(head -1 "$plan")" = "---" ] && echo 0 || echo 1)"
done

printf '\n%d / %d checks passed\n' "$pass" "$((pass + fail))"
[ "$fail" -eq 0 ]
