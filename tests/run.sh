#!/usr/bin/env bash
# tests/run.sh — single entrypoint for the notes.nvim test suite.
#
# Usage: ./tests/run.sh
#
# Runs every tests/test_*.sh (bash) and tests/test_*.lua (plain `lua`, no
# nvim needed) script, reporting a pass/fail summary. Each script is
# responsible for its own isolated fixtures (temp NOTES_DIR, etc.) and must
# exit non-zero on failure.
set -uo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_dir"

pass=0
fail=0
failed_names=()

run_one() {
	local name="$1"
	shift
	printf '\n==> %s\n' "$name"
	if "$@"; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		failed_names+=("$name")
	fi
}

for script in tests/test_*.sh; do
	[ -e "$script" ] || continue
	run_one "$script" bash "$script"
done

for script in tests/test_*.lua; do
	[ -e "$script" ] || continue
	run_one "$script" lua "$script"
done

printf '\n%d script(s) passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
	printf 'Failed: %s\n' "${failed_names[*]}"
	exit 1
fi
