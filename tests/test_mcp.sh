#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state_dir=$(mktemp -d)
stderr_file=$(mktemp)
trap 'rm -rf "$state_dir" "$stderr_file"' EXIT

initialize_request='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"notes-mcp-test","version":"1"}}}'
response=$(
	printf '%s\n' "$initialize_request" |
		XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
			--cmd "set runtimepath+=$repo_dir" \
			-c "lua require('notes.mcp').start()" 2>"$stderr_file"
)

printf '%s\n' "$response" | jq -e '.result.capabilities.tools | type == "object"' >/dev/null

printf 'MCP initialize response uses object-shaped tool capabilities\n'

tools_list_request='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
response=$(
	printf '%s\n' "$tools_list_request" |
		XDG_STATE_HOME="$state_dir" nvim --clean --headless -i NONE \
			--cmd "set runtimepath+=$repo_dir" \
			-c "lua require('notes.mcp').start()" 2>"$stderr_file"
)

printf '%s\n' "$response" | jq -e '
	[.result.tools[].inputSchema | .. | objects | select(
		.type == "object" or ((.type | type) == "array" and (.type | index("object")) != null)
	)]
	| length > 0 and all(
		.additionalProperties == false and
		((.required // []) | sort) == (((.properties // {}) | keys) | sort)
	)
' >/dev/null

printf 'MCP tool input schemas satisfy strict object requirements\n'
