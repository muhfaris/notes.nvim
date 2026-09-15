-- lua/notes/mcp/init.lua
--- MCP (Model Context Protocol) server for notes.nvim.
--- Runs as a stdio-based JSON-RPC server inside `nvim --headless`.
--- Exposes tools so AI agents (CodeCompanion.nvim) can read/write/search notes
--- without manually traversing the filesystem.
---
--- This module is the slim bootstrap: JSON-RPC transport, request dispatch,
--- and tool registry assembly. Tool implementations live in
--- `lua/notes/mcp/tools/*.lua`; shared helpers live in `lua/notes/mcp/shared.lua`.

local M = {}

local shared = require("notes.mcp.shared")
local encode_json = shared.encode_json
local decode_json = shared.decode_json
local notes_dir = shared.notes_dir

-- ── JSON-RPC Transport ─────────────────────────────────────────────────

local function send_response(id, result)
	local msg = encode_json({
		jsonrpc = "2.0",
		id = id,
		result = result,
	})
	if msg == nil then
		msg = '{"jsonrpc":"2.0","id":'
			.. tostring(id)
			.. ',"error":{"code":-32603,"message":"failed to encode response"}}'
	end
	io.stdout:write(msg .. "\n")
	io.stdout:flush()
end

local function send_error(id, code, message, data)
	local err = { code = code, message = message }
	if data then
		err.data = data
	end
	local msg = encode_json({
		jsonrpc = "2.0",
		id = id,
		error = err,
	})
	if msg == nil then
		msg = '{"jsonrpc":"2.0","id":'
			.. tostring(id)
			.. ',"error":{"code":-32603,"message":"failed to encode response"}}'
	end
	io.stdout:write(msg .. "\n")
	io.stdout:flush()
end

local function send_tool_result(id, text)
	send_response(id, {
		content = { { type = "text", text = text } },
	})
end

-- ── Tool Registry ──────────────────────────────────────────────────────

-- One module per tool; add a new tool by creating a file under
-- lua/notes/mcp/tools/ and registering its module name here.
local TOOL_MODULES = {
	"notes.mcp.tools.list",
	"notes.mcp.tools.search",
	"notes.mcp.tools.read",
	"notes.mcp.tools.create",
	"notes.mcp.tools.search_content",
	"notes.mcp.tools.backlinks",
	"notes.mcp.tools.get_metadata",
	"notes.mcp.tools.delete",
	"notes.mcp.tools.update",
	"notes.mcp.tools.recent",
	"notes.mcp.tools.tasks",
	"notes.mcp.tools.toggle_task",
	"notes.mcp.tools.add_subtask",
	"notes.mcp.tools.board_status",
	"notes.mcp.tools.rollover_tasks",
	"notes.mcp.tools.history",
	"notes.mcp.tools.diff",
}

local function normalize_strict_schema(schema, optional)
	if type(schema) ~= "table" then
		return
	end

	local schema_type = schema.type
	if optional and type(schema_type) == "string" then
		schema.type = { schema_type, "null" }
	end

	if schema_type == "object" then
		local originally_required = {}
		for _, name in ipairs(schema.required or {}) do
			originally_required[name] = true
		end

		local required = {}
		for name, property in pairs(schema.properties or {}) do
			normalize_strict_schema(property, not originally_required[name])
			required[#required + 1] = name
		end
		table.sort(required)
		schema.required = required
		schema.additionalProperties = false
	elseif schema_type == "array" then
		normalize_strict_schema(schema.items, false)
	end
end

local tools = {}
for _, mod in ipairs(TOOL_MODULES) do
	local ok, tool = pcall(require, mod)
	if ok and tool then
		-- Strict function schemas require closed objects and every property in the
		-- required array. Preserve optional semantics by making formerly optional
		-- properties nullable. Enforce this at the registry boundary so new tools
		-- cannot accidentally advertise an invalid schema.
		normalize_strict_schema(tool.inputSchema, false)
		tools[#tools + 1] = tool
	else
		-- A broken tool module must not kill the server.
		io.stderr:write("notes-mcp: failed to load tool module " .. mod .. ": " .. tostring(tool) .. "\n")
		io.stderr:flush()
	end
end

-- Build lookup table
local tool_map = {}
for _, t in ipairs(tools) do
	tool_map[t.name] = t
end

local function omit_json_nulls(value)
	if value == vim.NIL then
		return nil
	end
	if type(value) ~= "table" then
		return value
	end

	local cleaned = {}
	for key, child in pairs(value) do
		local normalized = omit_json_nulls(child)
		if normalized ~= nil then
			cleaned[key] = normalized
		end
	end
	return cleaned
end

-- ── MCP Protocol Handler ───────────────────────────────────────────────

local function handle_request(request)
	local id = request.id
	local method = request.method
	local params = request.params or {}

	-- Notifications carry no id and must never produce a response.
	if method == "notifications/initialized" then
		return
	end

	if method == "initialize" then
		send_response(id, {
			protocolVersion = "2024-11-05",
			capabilities = {
				-- MCP capability declarations are JSON objects. Neovim encodes an
				-- empty Lua table as [], which strict clients such as Codex reject.
				tools = vim.empty_dict(),
			},
			serverInfo = {
				name = "notes-mcp",
				version = "0.1.0",
			},
		})
		return
	end

	if method == "tools/list" then
		local tool_defs = {}
		for _, t in ipairs(tools) do
			tool_defs[#tool_defs + 1] = {
				name = t.name,
				description = t.description,
				inputSchema = t.inputSchema,
			}
		end
		send_response(id, { tools = tool_defs })
		return
	end

	if method == "tools/call" then
		local tool_name = params.name
		local args = omit_json_nulls(params.arguments or {})

		local tool = tool_map[tool_name]
		if not tool then
			send_error(id, -32601, "Method not found: " .. tostring(tool_name))
			return
		end

		local ok, result = pcall(tool.handler, args)
		if not ok then
			send_error(id, -32603, "Internal error", result)
			return
		end

		send_tool_result(id, result)
		return
	end

	-- Unknown method
	send_error(id, -32601, "Method not found: " .. tostring(method))
end

-- ── Main Loop ──────────────────────────────────────────────────────────

function M.start()
	-- Notify on stderr that the server started
	io.stderr:write("notes-mcp: server started\n")
	io.stderr:flush()

	-- Ensure notes directory exists
	if vim.fn.isdirectory(notes_dir) == 0 then
		vim.fn.mkdir(notes_dir, "p")
	end

	-- Read JSON-RPC messages from stdin (line-delimited)
	while true do
		local line = io.stdin:read("*line")
		if not line then
			break
		end

		-- Skip empty lines
		if line ~= "" then
			local request = decode_json(line)
			if not request then
				io.stderr:write("notes-mcp: failed to parse request: " .. line .. "\n")
				io.stderr:flush()
			else
				-- Handle the request
				local ok, err = pcall(handle_request, request)
				if not ok then
					io.stderr:write("notes-mcp: handler error: " .. tostring(err) .. "\n")
					io.stderr:flush()
					if request.id then
						send_error(request.id, -32603, "Internal error", tostring(err))
					end
				end
			end
		end
	end

	io.stderr:write("notes-mcp: server shutting down\n")
	io.stderr:flush()

	-- Exit nvim cleanly once stdin is exhausted (client disconnected).
	-- Must be scheduled: a direct qa! during the -c startup phase is ignored
	-- in headless mode and would leave the process alive forever.
	vim.schedule(function()
		vim.cmd("qa!")
	end)
end

return M
