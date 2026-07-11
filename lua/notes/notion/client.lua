-- lua/notes/notion/client.lua
local M = {}

local BASE_URL = "https://api.notion.com/v1/"
local NOTION_VERSION = "2022-06-28"

--- Perform an asynchronous HTTP request to the Notion API using curl via vim.system.
--- @param token string The Notion Integration Token.
--- @param method string HTTP Method: "GET", "POST", "PATCH", "DELETE".
--- @param endpoint string The API endpoint (e.g., "pages", "blocks/xyz/children").
--- @param payload table|nil The Lua table payload to encode as JSON.
--- @param callback function Called with (success: boolean, response_data: table|string).
local function request(token, method, endpoint, payload, callback)
	if vim.fn.executable("curl") == 0 then
		callback(false, "curl executable not found on system path")
		return
	end

	local url = BASE_URL .. endpoint
	local cmd = {
		"curl",
		"-s",
		"-X",
		method,
		url,
		"-H",
		"Authorization: Bearer " .. token,
		"-H",
		"Content-Type: application/json",
		"-H",
		"Notion-Version: " .. NOTION_VERSION,
	}

	local stdin_data = nil
	if payload then
		local ok, json_str = pcall(vim.json.encode, payload)
		if not ok then
			callback(false, "Failed to encode JSON payload: " .. tostring(json_str))
			return
		end
		table.insert(cmd, "--data")
		table.insert(cmd, "@-")
		stdin_data = json_str
	end

	vim.system(cmd, { stdin = stdin_data }, function(obj)
		if obj.code ~= 0 then
			callback(false, "curl command failed: " .. (obj.stderr or ""))
			return
		end

		local raw_resp = obj.stdout or ""
		if raw_resp == "" then
			callback(true, {})
			return
		end

		local decode_ok, decoded = pcall(vim.json.decode, raw_resp)
		if not decode_ok then
			callback(false, "Failed to decode Notion response JSON: " .. raw_resp)
			return
		end

		if decoded.object == "error" then
			callback(false, "Notion API Error: " .. (decoded.message or "Unknown error"))
			return
		end

		callback(true, decoded)
	end)
end

--- Create a new page in a database.
--- @param token string
--- @param database_id string
--- @param properties table
--- @param children table
--- @param callback function
function M.create_page(token, database_id, properties, children, callback)
	local payload = {
		parent = { database_id = database_id },
		properties = properties,
		children = children,
	}
	request(token, "POST", "pages", payload, callback)
end

--- Update page properties.
--- @param token string
--- @param page_id string
--- @param properties table
--- @param callback function
function M.update_page_properties(token, page_id, properties, callback)
	local payload = {
		properties = properties,
	}
	request(token, "PATCH", "pages/" .. page_id, payload, callback)
end

--- Retrieve children blocks of a block/page.
--- @param token string
--- @param block_id string
--- @param callback function
function M.get_block_children(token, block_id, callback)
	request(token, "GET", "blocks/" .. block_id .. "/children", nil, callback)
end

--- Delete a specific block.
--- @param token string
--- @param block_id string
--- @param callback function
function M.delete_block(token, block_id, callback)
	request(token, "DELETE", "blocks/" .. block_id, nil, callback)
end

--- Append children blocks to a block/page.
--- @param token string
--- @param block_id string
--- @param children table
--- @param callback function
function M.append_block_children(token, block_id, children, callback)
	local payload = {
		children = children,
	}
	request(token, "PATCH", "blocks/" .. block_id .. "/children", payload, callback)
end

return M
