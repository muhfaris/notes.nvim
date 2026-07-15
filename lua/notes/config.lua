-- lua/notes/config.lua
local M = {}

-- Default configuration
M.config = {
	notes_dir = vim.fn.expand("~/.notes"),
	date_format = "%Y-%m-%d",
	time_format = "%H:%M:%S",
	editor_style = "current", -- "current" (default), "float", "tab", "split", or "vsplit"
	auto_toc = true,
	toc_max_level = 4,
	template = [[---
title: "%TITLE%"
date: "%DATE%"
tags: []
summary: ""
---

# %TITLE%

## Description

%BODY%
]],
	daily_template = [[---
title: "%TITLE%"
date: "%DATE%"
tags: ["daily"]
summary: ""
---

# %TITLE%

## Focus

## Standup / Meetings

## Tasks / Notes
]],
	templates = {
		default = [[---
title: "%TITLE%"
date: "%DATE%"
tags: []
summary: ""
---

# %TITLE%

## Description

%BODY%
]],
		rfc = [[---
title: "RFC: %TITLE%"
date: "%DATE%"
tags: ["rfc"]
summary: ""
---

# RFC: %TITLE%

## Background

## Proposal

## Alternative Solutions
]],
		meeting = [[---
title: "Meeting: %TITLE%"
date: "%DATE%"
tags: ["meeting"]
summary: ""
---

# Meeting: %TITLE%

## Attendees

## Agenda

## Action Items
]],
		bug = [[---
title: "Bug: %TITLE%"
date: "%DATE%"
tags: ["bug"]
summary: ""
---

# Bug: %TITLE%

## Symptoms

## Reproduction Steps

## Root Cause Analysis

## Resolution
]],
		til = [[---
title: "TIL: %TITLE%"
date: "%DATE%"
tags: ["til"]
summary: ""
---

# TIL: %TITLE%

## Concept

## Code / CLI Example

## Gotchas

## References
]],
	},
	keymaps = {
		n = {
			["<leader>nn"] = "new",
			["<leader>nd"] = "daily",
			["<leader>nl"] = "list",
			["<leader>ne"] = "explorer",
			["<leader>ns"] = "search",
			["<leader>np"] = "paste_image",
			["<leader>nc"] = "quick_capture",
			["<leader>nto"] = "outline",
			["<leader>ntc"] = "insert_toc",
			["<leader>ni"] = "choose_icon",
		},
	},
	key_desc = {
		new = "Notes: New",
		daily = "Notes: Open Daily",
		list = "Notes: List",
		explorer = "Notes: Explorer",
		search = "Notes: Search",
		paste_image = "Notes: Paste Image",
		migrate = "Notes: Migrate",
		tags = "Notes: Browse Tags",
		rename = "Notes: Rename",
		delete = "Notes: Delete",
		backlinks = "Notes: Backlinks",
		tasks = "Notes: Tasks",
		daily_prev = "Notes: Previous Daily",
		daily_next = "Notes: Next Daily",
		notion_sync = "Notes: Notion Sync",
		quick_capture = "Notes: Quick Capture Scratchpad",
		outline = "Notes: Interactive Outline",
		insert_toc = "Notes: Insert Table of Contents",
		choose_icon = "Notes: Choose Icon",
	},
	length_summary = 140,
	length_title = 60,
	notion = {
		enabled = false,
		token = nil,
		sync_on_save = true,
		directory_mappings = {},
		tag_mappings = {},
		default_database = {
			database_id = nil,
			properties = {
				title = "Name",
				tags = "Tags",
				date = "Date",
				summary = "Summary",
			},
		},
	},
	git = {
		enabled = false,
		auto_commit = true,
		commit_message = "update notes",
	},
	fn = {
		new = function(title)
			require("notes.ui").new_note(title)
		end,
		daily = function()
			require("notes.ui").daily_note()
		end,
		list = function()
			require("notes.ui").list_notes()
		end,
		explorer = function()
			require("notes.ui").toggle_explorer()
		end,
		search = function()
			require("notes.ui").search_notes()
		end,
		paste_image = function()
			require("notes.utils").paste_image()
		end,
		migrate = function()
			require("notes.ui").migrate_notes()
		end,
		tags = function()
			require("notes.ui").list_tags()
		end,
		rename = function()
			require("notes.ui").rename_active_note()
		end,
		delete = function()
			require("notes.ui").delete_active_note()
		end,
		backlinks = function()
			require("notes.ui").list_backlinks()
		end,
		tasks = function()
			require("notes.ui").list_tasks()
		end,
		daily_prev = function()
			require("notes.ui").daily_prev()
		end,
		daily_next = function()
			require("notes.ui").daily_next()
		end,
		notion_sync = function()
			require("notes.notion.sync").sync_active_note()
		end,
		quick_capture = function()
			require("notes.ui").quick_capture()
		end,
		outline = function()
			require("notes.ui").outline()
		end,
		insert_toc = function()
			require("notes.ui").insert_toc()
		end,
		choose_icon = function()
			require("notes.ui").choose_icon()
		end,
	},
}

-- Function to set up the plugin
M.setup = function(opts)
	opts = opts or {}
	if opts.keymaps == false then
		M.config.keymaps = {}
		opts.keymaps = nil
	end
	M.config = vim.tbl_deep_extend("force", M.config, opts)

	if opts.notes_dir then
		M.config.notes_dir = vim.fn.expand(opts.notes_dir)
	end

	-- Ensure the notes directory exists
	if vim.fn.isdirectory(M.config.notes_dir) == 0 then
		vim.fn.mkdir(M.config.notes_dir, "p")
	end
end

M.get_config = function()
	return M.config
end

return M
