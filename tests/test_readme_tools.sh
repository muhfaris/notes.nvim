#!/usr/bin/env bash
# README/MCP-tool drift guard: every registered MCP tool must be documented.
#
# The README's `### Exposed tools` table is the only place a user (or agent)
# learns which tools exist. It silently fell 7 tools behind — exactly the set
# added by the later MCP plans and covered by tests/test_mcp_tools.sh — because
# nothing connected the two. Tool names are therefore sourced from the tool
# modules, never from the README: only then does a *new* undocumented tool fail.
#
# Read-only. No Neovim, no notes dir.
set -uo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tools_dir="$repo_dir/lua/notes/mcp/tools"
readme="$repo_dir/README.md"

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

if [ ! -d "$tools_dir" ]; then
	printf 'FAIL - no %s\n' "$tools_dir"
	exit 1
fi

if [ ! -f "$readme" ]; then
	printf 'FAIL - no %s\n' "$readme"
	exit 1
fi

# Registered tool names, straight from the modules that register them.
mapfile -t tools < <(grep -rh '^[[:space:]]*name = "notes_' "$tools_dir" |
	sed 's/.*name = "\(notes_[a-z_]*\)".*/\1/' | sort -u)

if [ "${#tools[@]}" -eq 0 ]; then
	printf 'FAIL - no tool names found under %s\n' "$tools_dir"
	exit 1
fi

# Each tool needs its own table row (`| \`notes_x\` |`), not a passing mention
# in prose — a mention would let the table rot while this test stayed green.
missing=()
for tool in "${tools[@]}"; do
	if grep -q "| \`$tool\` |" "$readme"; then
		check "README documents $tool" "1"
	else
		check "README documents $tool" "0"
		missing+=("$tool")
	fi
done

# Row count catches the inverse failure: a README row for a tool that no longer
# exists (renamed, deleted) also leaves the two lists out of step.
doc_rows=$(grep -c '^| `notes_[a-z_]*` |' "$readme" || true)
if [ "$doc_rows" = "${#tools[@]}" ]; then
	check "table row count matches registered tools ($doc_rows)" "1"
else
	check "table row count matches registered tools (registry ${#tools[@]}, README $doc_rows)" "0"
fi

if [ "${#missing[@]}" -gt 0 ]; then
	printf '\nUndocumented tools: %s\n' "${missing[*]}"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
