-- lua/notes/config.lua
local M = {}

-- Default configuration
M.config = {
	notes_dir = vim.fn.expand("~/.notes"),
	date_format = "%Y-%m-%d",
	time_format = "%H:%M:%S",
	editor_style = "current", -- "current" (default), "float", "tab", "split", or "vsplit"
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
	},
	keymaps = {},
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
	},
}

-- Function to set up the plugin
M.setup = function(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

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
