#!/usr/bin/env bash
# Grammar checks for the checklist-line single owner in notes.shared.tasks —
# M.parse_task_line / M.is_task_line / M.box_status / M.status_box /
# M.is_open_box / M.set_box — plus the editor toggle and the scanner built on
# top of them. These pin the consolidation: before it, the same line was
# spelled nine different ways across seven files, so a box glyph could mean
# one thing to the scanner and another to the Home dashboard.
#
# The grammar module uses vim.fn/vim.trim, so this wraps the checks in
# tests/task_grammar.lua instead of letting run.sh execute them under plain
# `lua` (which is what tests/test_*.lua scripts get). Runs against isolated
# temp dirs — never touches the caller's real vault.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
notes_dir=$(mktemp -d)
state_dir=$(mktemp -d)
trap 'rm -rf "$notes_dir" "$state_dir"' EXIT

NOTES_DIR="$notes_dir" XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
	--cmd "set runtimepath+=$repo_dir" \
	+"luafile $repo_dir/tests/task_grammar.lua"
