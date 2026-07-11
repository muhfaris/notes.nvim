-- lua/notes/notion/sync.lua
local M = {}

local client = require("notes.notion.client")
local resolver = require("notes.notion.resolver")
local translator = require("notes.notion.translator")

local sync_timers = {}

--- Delete blocks sequentially to respect rate limiting.
local function delete_blocks(token, block_ids, index, callback)
	if index > #block_ids then
		callback(true)
		return
	end

	client.delete_block(token, block_ids[index], function(ok, err)
		-- We continue deleting even if one block deletion fails, but we can log it
		if not ok then
			vim.schedule(function()
				vim.diagnostic.log = vim.diagnostic.log or print
				-- Quiet failure, continue
			end)
		end
		delete_blocks(token, block_ids, index + 1, callback)
	end)
end

--- Append blocks in chunks of 100 to respect Notion's payload limits.
local function append_blocks_chunked(token, page_id, blocks, start_idx, callback)
	if start_idx > #blocks then
		callback(true)
		return
	end

	local chunk = {}
	for j = start_idx, math.min(start_idx + 99, #blocks) do
		table.insert(chunk, blocks[j])
	end

	client.append_block_children(token, page_id, chunk, function(ok, err)
		if not ok then
			callback(false, err)
			return
		end
		append_blocks_chunked(token, page_id, blocks, start_idx + 100, callback)
	end)
end

--- Syncs a specific Neovim buffer to Notion.
--- @param buf number The buffer number.
function M.sync_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local filepath = vim.api.nvim_buf_get_name(buf)
	if filepath == "" or vim.fn.filereadable(filepath) == 0 then
		return
	end

	local config = require("notes.config").get_config()
	if not config.notion or not config.notion.enabled or not config.notion.token then
		return
	end

	local parser = require("notes.parser")
	local metadata, body = parser.read_file(filepath)
	if not metadata then
		return
	end

	local database_id, properties_mapping = resolver.resolve_database(filepath, metadata)
	if not database_id then
		return
	end

	local blocks = translator.translate_to_blocks(body)
	local token = config.notion.token
	if type(token) == "function" then
		token = token()
	end

	if not token or token == "" then
		vim.schedule(function()
			vim.notify("Notion sync failed: Notion token is empty or invalid", vim.log.levels.ERROR)
		end)
		return
	end

	local page_id = resolver.get_page_id(metadata)

	-- Build properties payload
	local properties = {}
	if properties_mapping.title then
		properties[properties_mapping.title] = {
			title = {
				{ text = { content = metadata.title or vim.fn.fnamemodify(filepath, ":t:r") } }
			}
		}
	end

	if properties_mapping.tags and metadata.tags and #metadata.tags > 0 then
		local select_list = {}
		for _, tag in ipairs(metadata.tags) do
			table.insert(select_list, { name = tag })
		end
		properties[properties_mapping.tags] = {
			multi_select = select_list
		}
	end

	if properties_mapping.date and metadata.date and metadata.date ~= "" then
		local date_val = metadata.date:match("^%d%d%d%d%-%d%d%-%d%d")
		if date_val then
			properties[properties_mapping.date] = {
				date = { start = date_val }
			}
		end
	end

	if properties_mapping.summary and metadata.summary and metadata.summary ~= "" then
		properties[properties_mapping.summary] = {
			rich_text = {
				{ text = { content = metadata.summary } }
			}
		}
	end

	if not page_id then
		-- Create new page
		vim.schedule(function()
			vim.notify("Notion: Creating new page...", vim.log.levels.INFO)
		end)

		local initial_blocks = {}
		local remaining_blocks = {}
		for i, block in ipairs(blocks) do
			if i <= 100 then
				table.insert(initial_blocks, block)
			else
				table.insert(remaining_blocks, block)
			end
		end

		client.create_page(token, database_id, properties, initial_blocks, function(success, response)
			if not success then
				vim.schedule(function()
					vim.notify("Notion sync failed (create): " .. tostring(response), vim.log.levels.ERROR)
				end)
				return
			end

			local new_page_id = response.id

			-- Write page ID back to note file frontmatter
			vim.schedule(function()
				resolver.write_page_id(filepath, new_page_id)
				if vim.api.nvim_buf_is_valid(buf) then
					vim.cmd("checktime " .. buf)
				end
			end)

			if #remaining_blocks > 0 then
				append_blocks_chunked(token, new_page_id, remaining_blocks, 1, function(append_ok, append_err)
					if not append_ok then
						vim.schedule(function()
							vim.notify("Notion sync failed appending remaining blocks: " .. tostring(append_err), vim.log.levels.ERROR)
						end)
					else
						vim.schedule(function()
							vim.notify("Notion: Page created and fully synced!", vim.log.levels.INFO)
						end)
					end
				end)
			else
				vim.schedule(function()
					vim.notify("Notion: Page created and fully synced!", vim.log.levels.INFO)
				end)
			end
		end)
	else
		-- Update existing page
		vim.schedule(function()
			vim.notify("Notion: Syncing updates...", vim.log.levels.INFO)
		end)

		client.update_page_properties(token, page_id, properties, function(success, response)
			if not success then
				vim.schedule(function()
					vim.notify("Notion sync failed (update properties): " .. tostring(response), vim.log.levels.ERROR)
				end)
				return
			end

			-- Clear old blocks and write new ones
			client.get_block_children(token, page_id, function(get_ok, get_resp)
				if not get_ok then
					vim.schedule(function()
						vim.notify("Notion sync failed fetching block children: " .. tostring(get_resp), vim.log.levels.ERROR)
					end)
					return
				end

				local child_ids = {}
				if get_resp.results then
					for _, block in ipairs(get_resp.results) do
						table.insert(child_ids, block.id)
					end
				end

				delete_blocks(token, child_ids, 1, function(delete_ok)
					if not delete_ok then
						vim.schedule(function()
							vim.notify("Notion sync failed clearing old blocks", vim.log.levels.ERROR)
						end)
						return
					end

					append_blocks_chunked(token, page_id, blocks, 1, function(append_ok, append_err)
						if not append_ok then
							vim.schedule(function()
								vim.notify("Notion sync failed appending blocks: " .. tostring(append_err), vim.log.levels.ERROR)
							end)
						else
							vim.schedule(function()
								vim.notify("Notion: Note synced successfully!", vim.log.levels.INFO)
							end)
						end
					end)
				end)
			end)
		end)
	end
end

--- Debounced active note sync.
--- @param buf number
function M.sync_active_note_debounced(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if sync_timers[buf] then
		sync_timers[buf]:stop()
		sync_timers[buf]:close()
		sync_timers[buf] = nil
	end

	local uv = vim.uv or vim.loop
	local timer = uv.new_timer()
	sync_timers[buf] = timer
	timer:start(2000, 0, vim.schedule_wrap(function()
		if sync_timers[buf] == timer then
			sync_timers[buf] = nil
		end
		timer:stop()
		timer:close()
		M.sync_buffer(buf)
	end))
end

--- Sync the currently active buffer to Notion immediately.
function M.sync_active_note()
	local buf = vim.api.nvim_get_current_buf()
	M.sync_buffer(buf)
end

return M
