# notes.nvim - The Developer's Note-Taking Plugin for Neovim

`notes.nvim` is a premium, developer-centric note-taking plugin for Neovim. It transforms your markdown notes into an interactive, visual personal wiki with support for YAML frontmatter metadata, a dedicated explorer sidebar dashboard, daily journals, inter-note wiki-link navigation, interactive task lists, and cross-platform clipboard image pasting.

---

## ✨ Features

- **📝 Zero-Friction Note Creation**: Centered, rounded floating title input that focuses automatically without disrupting your workspace layout.
- **📅 Daily Journals**: Quick command (`:Notes daily`) to open or auto-generate today's journal entry.
- **🗂️ Interactive Explorer Sidebar**: A visual dashboard (`notes://explorer`) grouping notes by Year and Month. Navigate, rename, delete, or create notes directly from the panel.
- **🧮 Standard YAML Frontmatter**: Parses and writes frontmatter variables (`title`, `date`, `tags`, `summary`) automatically. Legacy note formats are read seamlessly via automatic fallback parsing.
- **🔗 Inter-note Wiki-Links**: Press `<CR>` on any `[[Linked Note]]` or `[[2026-07-10]]` to jump to it instantly. If the linked note doesn't exist, the plugin prompts to create it.
- **☑️ Task Checklists**: Easily toggle markdown checkbox items (`- [ ]` / `- [x]`) using `<leader>nt` (buffer-local, fully customizable).
- **🖼️ Portable Clipboard Image Pasting**: Paste images directly from your clipboard across Linux (X11 & Wayland), macOS, and Windows. Saves files into `notes_dir/images/` and links them with portable relative paths (`images/image.png`).
- **🔍 Telescope Integration**: Fuzzy find notes by title/tags/date via a clean column-based Telescope list (`:Notes list`), or live grep inside note content (`:Notes search`).
- **🧮 Markdown Table Math**: Excel-like cell calculation (`=SUM(A1:A3)`, `=AVG(...)`, arithmetic operations) overlaid via non-destructive virtual text. Updates automatically on save and mode changes.
- **📋 Dynamic Custom Templates**: Merges built-in Lua templates with your custom templates defined as files in `<notes_dir>/templates/`. All template files are excluded from core search, explorer, and autocompletion lists to keep your workspace clean.

---

## 📦 Installation

Install `notes.nvim` using your favorite package manager.

### Lazy.nvim

```lua
return {
  "muhfaris/notes.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",       -- Fuzzy finder integration
    "nvim-lua/plenary.nvim",               -- Required utility functions
  },
  config = function()
    require("notes").setup {
      notes_dir = "~/.notes",              -- Directory where notes/images are stored
      length_title = 60,                   -- Maximum title length (characters)
      length_summary = 140,                -- Maximum summary length (characters)
      editor_style = "current",            -- "current" (default), "float", "tab", "split", or "vsplit"
      keymaps = {
        n = {
          ["<leader>nn"] = "new",          -- Create a new note
          ["<leader>nd"] = "daily",        -- Open today's daily journal
          ["<leader>nl"] = "list",         -- List notes using Telescope
          ["<leader>ne"] = "explorer",     -- Toggle the sidebar explorer
          ["<leader>ns"] = "search",       -- Live search note contents
          ["<leader>np"] = "paste_image",  -- Paste clipboard image
          ["<leader>nc"] = "quick_capture",-- Quick scratchpad capture
        },
      },
    }
  end,
}
```

---

## 🚀 Usage & Commands

The plugin registers a unified `:Notes` user command with completion support:

| Command | Action |
| :--- | :--- |
| `:Notes new [title]` | Open floating popup to create a note. |
| `:Notes daily` | Open or create today's journal entry. |
| `:Notes explorer` | Toggle the visual explorer sidebar. |
| `:Notes list` | List notes with Telescope formatted in columns. |
| `:Notes search` | Search (live grep) note contents. |
| `:Notes paste_image` | Paste clipboard image and insert relative markdown link. |
| `:Notes capture` | Open a temporary scratchpad to quickly append thoughts/tasks to today's daily note. |

---

## 🗂️ Notes Explorer Sidebar

Toggle the sidebar with `:Notes explorer` or your bound key.

### Keymaps inside the Explorer buffer:
* `<CR>` / `o`: Open the highlighted note.
* `a`: Add a new file or directory (automatically detects: ends with `/` for directory, otherwise creates a file).
* `d`: Delete the highlighted note (requires confirmation).
* `r`: Rename the note title (automatically updates filename and YAML frontmatter title metadata).
* `m`: Move the highlighted note to a new destination path (updates active buffer if open).
* `c`: Copy the highlighted note path to the clipboard register.
* `p`: Paste the copied note from the clipboard register into the current directory context.
* `n`: Prompt to create a new note (opens template picker).
* `s`: Search inside note contents globally.
* `R`: Refresh/Reload the explorer directory structure.
* `q`: Close the explorer sidebar.
* `?`: Show the help popup displaying all available keymaps.

---

## ✍️ Markdown Buffer-local Keymaps

When editing markdown files in your `notes_dir`, the plugin automatically activates buffer-local keymaps for fluid editing:

* **Wiki-link Jump (`<CR>`)**: Press `<CR>` while cursor is on `[[Link]]` to navigate to that note.
* **Task Toggle (`<leader>nt`)**: Toggle checklist state on the current line between `- [ ]` and `- [x]`.
* **Highlight Toggle (`<leader>nh`)**: Highlight the selected text in visual mode or toggle highlighting on the word under the cursor using `==` tags.

---

## 🧮 Markdown Table Math

`notes.nvim` features an automated Excel-like spreadsheet calculation engine for standard Markdown tables. Formula cells remain fully editable as standard text, and computed values are displayed as non-destructive virtual text next to the cell.

### How it works:
1. **Coordinate System**:
   - Columns are lettered (`A`, `B`, `C`...) starting from the leftmost column in the table.
   - Rows are numbered (`1`, `2`, `3`...) starting from the first data row (header and separator rows are skipped).
2. **Formulas**:
   - Begin with `=` (e.g., `=B1*C1`).
   - Supported math functions: `SUM(range)`, `AVG(range)`, `COUNT(range)`, `MIN(range)`, `MAX(range)` (e.g. `=SUM(D1:D5)`).
   - Basic arithmetic: `+`, `-`, `*`, `/`, parenthesis `()`, and numbers.
3. **Execution**:
   - Formulas evaluate automatically on `InsertLeave` and `BufWritePre` (when saving the file).
   - Displays clear error hints on invalid inputs (e.g., `⚠️ circular` for circular dependencies, `⚠️ #DIV/0!` for division by zero, `⚠️ #VALUE!` for invalid calculations).

#### Example:
```markdown
| Item   | Price | Qty | Total       |
|--------|-------|-----|-------------|
| Apple  | 10    | 3   | =B1*C1      |
| Banana | 20    | 2   | =B2*C2      |
| Total  |       |     | =SUM(D1:D2) |
```

---

## 📄 Configuration Options

```lua
require("notes").setup({
  notes_dir = vim.fn.expand("~/.notes"),   -- Notes workspace directory
  date_format = "%Y-%m-%d",                -- Date format used in templates
  time_format = "%H:%M:%S",                -- Time format used in templates
  length_title = 60,                       -- Char limit for note titles
  length_summary = 140,                    -- Char limit for summary frontmatter field
  editor_style = "current",                -- "current" (default), "float" (floating popup), "tab" (new tab page), "split" (horizontal split), or "vsplit" (vertical split)
  
  -- Default Markdown template
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

  -- Optional Git Auto-Commit Integration
  git = {
    enabled = false,                       -- Toggle Git auto-commit support
    auto_commit = true,                    -- Commit automatically on save/rename/delete
    commit_message = "update notes",       -- Base commit message
  },

  -- Default keymaps are registered automatically. Override any keys below:
  keymaps = {
    n = {
      ["<leader>nn"] = "new",
      ["<leader>nd"] = "daily",
      ["<leader>nl"] = "list",
      ["<leader>ne"] = "explorer",
      ["<leader>ns"] = "search",
      ["<leader>np"] = "paste_image",
      ["<leader>nc"] = "quick_capture",
    }
  }
  -- Set keymaps = false to disable default bindings completely
})
```

---

## 🔄 Notion Integration (Optional)

`notes.nvim` features an optional, non-blocking asynchronous Notion synchronization engine. When enabled, your local markdown notes are translated into Notion blocks and synced to target databases based on customizable folder-mapping, tag-routing, or a fallback default database.

Syncing is triggered automatically on file save (debounced for performance) or manually via user command. Because the engine runs asynchronously in background processes using Neovim's `vim.system` and `curl`, Neovim will never freeze or hang during sync operations.

### Configuration

Add the `notion` configuration block to your `setup` options:

```lua
require("notes").setup {
  notes_dir = "~/.notes",
  
  -- Optional Notion Configuration
  notion = {
    enabled = true,
    -- Notion Integration Token:
    -- 1. Plain string: "secret_your_notion_token"
    -- 2. Environment variable: os.getenv("NOTION_TOKEN")
    -- 3. Dynamic function (e.g. password manager 'pass'):
    token = function()
      return vim.fn.system("pass show notion/token"):gsub("%s+", "")
    end,
    sync_on_save = true,                             -- Debounced sync on BufWritePost
    
    -- Rule 1: Map specific folders to target Notion databases
    directory_mappings = {
      ["/rfc/"] = {
        database_id = "your_notion_rfc_database_id",
        properties = {
          title = "RFC Title",                       -- Notion column names
          tags = "Tags",
          date = "Date Created",
          summary = "Abstract",
        }
      },
      ["/meetings/"] = {
        database_id = "your_notion_meetings_database_id",
        properties = {
          title = "Meeting Name",
          date = "Date",
        }
      }
    },
    
    -- Rule 2: Map tags to target Notion databases
    tag_mappings = {
      ["daily"] = {
        database_id = "your_notion_journal_database_id",
        properties = {
          title = "Name",
          tags = "Journal Tags",
        }
      }
    },

    -- Fallback default database mapping
    default_database = {
      database_id = "your_notion_general_database_id",
      properties = {
        title = "Name",
        tags = "Tags",
        date = "Date",
        summary = "Summary",
      }
    }
  }
}
```

### Commands

| Command | Action |
| :--- | :--- |
| `:Notes notion sync` | Manually trigger immediate synchronization of the active note. |

### How It Works

1. **Routing Resolution**: When a sync is triggered, the engine resolves which database to target in the following order:
   - Check if `notion_database_id` is set directly in the note's YAML frontmatter.
   - Check if the note's file path matches any key in `directory_mappings`.
   - Check if any tag in the note's YAML frontmatter matches a key in `tag_mappings`.
   - Fall back to the configured `default_database`.
2. **Page Linkage**: Upon the first synchronization of a local note, a Notion page is created in the resolved database. The resulting Notion Page ID is written back to the note's YAML frontmatter as `notion_page_id: "..."`.
3. **Subsequent Saves**: When you save a note that already contains a `notion_page_id`, the engine updates the page properties (name, tags, summary, date) and cleanly syncs/re-builds the block contents in the background.

---

## 💾 Git Auto-Commit Integration (Optional)

`notes.nvim` includes an optional Git integration that automatically stages and commits your notes in the background. It is designed to be completely non-blocking, using Neovim's asynchronous process API (`vim.system`).

The plugin checks if Git is installed and whether your notes directory is a Git repository. If either check fails, the feature gracefully degrades and does nothing, preventing any editor crashes.

### Configuration

To enable the Git integration, add the `git` configuration table to your setup:

```lua
require("notes").setup({
  notes_dir = "~/.notes",
  git = {
    enabled = true,                        -- Enable Git integration
    auto_commit = true,                    -- Auto-commit changes on file writes/deletes/renames
    commit_message = "update notes",       -- Custom commit message
  }
})
```

### How It Works

1. **Automatic Saves**: Whenever you write/save a note buffer within your `notes_dir`, the plugin automatically runs `git add -A` and `git commit -m "<commit_message>"` in the background.
2. **File Operations**: Background commits are automatically generated for file actions that don't trigger normal buffer write events (e.g. deleting/renaming notes inside the explorer, saving a quick capture scratchpad, pasting images, and move operations).
3. **No Network Activity**: The plugin only performs `git add` and `git commit` operations. It never performs remote network operations like `git push` or `git pull`, ensuring offline compatibility and speed.

---

## 📋 Note Templates

`notes.nvim` provides a powerful note template engine. When creating a new note (via `:Notes new` or `n` in the explorer), a Telescope template picker lets you choose from pre-defined templates.

### Dynamic Placeholders
Within your templates, you can use the following standard placeholders which are resolved dynamically:
- `%TITLE%`: The title of the note.
- `%DATE%`: The current date formatted using `date_format`.
- `%BODY%`: Default content or blank space.

### 1. File-based Custom Templates
You can create custom templates as standard Markdown files inside the `templates/` folder of your notes directory:
- Path: `<notes_dir>/templates/<template-name>.md`
- The name of the file (excluding `.md`) will appear in the template selection picker.
- Any notes created from file-based templates are fully configured with standard YAML frontmatter.
- **Hygiene & Filtering**: To keep your workspace clean, any files/folders inside the `templates/` directory are automatically excluded from the Notes Explorer sidebar, global Telescope note lists, live grep content searches, and autocompletion lists.

### 2. Config-based Lua Templates
You can also define templates in your Neovim config Lua setup function under the `templates` key:
```lua
require("notes").setup({
  notes_dir = "~/.notes",
  templates = {
    custom_project = [[---
title: "%TITLE%"
date: "%DATE%"
tags: ["project"]
---
# Project: %TITLE%
- Task 1
- Task 2
]]
  }
})
```

#### Pre-defined Templates
The plugin comes built-in with several standard templates:
- `bug`: For bug reports and tracking.
- `documentation`: For tech specs and library docs.
- `job_application`: For tracking company applications.
- `meeting`: For meeting minutes, agendas, and action items.
- `release`: For application release notes.
- `rfc`: For Request for Comments designs.
- `til`: For "Today I Learned" quick learnings.
- `daily`: Default template for daily journals.



