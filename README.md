# notes.nvim - The Developer's Note-Taking Plugin for Neovim

`notes.nvim` is a premium, developer-centric note-taking plugin for Neovim. It transforms your markdown notes into an interactive, visual personal wiki with support for YAML frontmatter metadata, a dedicated explorer sidebar dashboard, daily journals, inter-note wiki-link navigation, interactive task lists, and cross-platform clipboard image pasting.

---

## ✨ Features

- **📝 Zero-Friction Note Creation**: Centered, rounded floating title input that focuses automatically without disrupting your workspace layout.
- **📅 Daily Journals**: Quick command (`:Notes daily`) to open or auto-generate today's journal entry.
- **🗂️ Interactive Explorer Sidebar**: A visual dashboard (`notes://explorer`) grouping notes by Year and Month. Navigate, rename, delete, or create notes directly from the panel.
- **🧮 Standard YAML Frontmatter**: Parses and writes frontmatter variables (`title`, `date`, `tags`, `summary`) automatically. Legacy note formats are read seamlessly via automatic fallback parsing.
- **🔗 Inter-note Wiki-Links**: Press `<CR>` on any `[[Linked Note]]` or `[[2026-07-10]]` to jump to it instantly. If the linked note doesn't exist, the plugin prompts to create it.
- **☑️ Task Checklists**: Easily toggle markdown checkbox items (`- [ ]` / `- [x]`) using `<leader>nt` (buffer-local, fully customizable). `<leader>nta` nests a subtask under the current task and gives it its own detail note, linked as `- [ ] [[ Parent/Child ]]`. Write the alias form `- [ ] [[ Parent/Child|label ]]` when a line should read differently from the child's title — the label wins over the resolved title, and the link still resolves normally.
- **🖼️ Portable Clipboard Image Pasting**: Paste images directly from your clipboard across Linux (X11 & Wayland), macOS, and Windows. Saves files into `notes_dir/images/` and links them with portable relative paths (`images/image.png`).
- **🔍 Telescope Integration**: Fuzzy find notes by title/tags/date via a clean column-based Telescope list (`:Notes list`), or live grep inside content (`:Notes search`).
- **🧮 Markdown Table Math**: Excel-like cell calculation (`=SUM(A1:A3)`, `=AVG(...)`, arithmetic operations) overlaid via non-destructive virtual text. Updates automatically on save and mode changes.
- **📜 Note Revision History & Diff Viewer**: Human-centric timeline view (`:Notes history` / `<leader>nh`) powered by Git. Features In-Picker Live Diff Preview (Quick Scan), `<Tab>` snapshot/diff toggle, native side-by-side split (`diffsplit`), and non-destructive revert.
- **📄 Dynamic Custom Templates**: Merges built-in Lua templates with your custom templates defined as files in `<notes_dir>/templates/`. All template files are excluded from core search, explorer, and autocompletion lists to keep your workspace clean.

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
          ["<leader>nh"] = "history",      -- Note revision history timeline
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
| `:Notes history` / `:Notes log` | Open human-centric revision history timeline for the active note. |
| `:Notes home` | Open the Notes Home dashboard in a dedicated window (recent notes + open tasks). |

---

## 🏠 Notes Home Dashboard

Open the dashboard with `:Notes home` or your bound key (global default:
`<leader>nm`). It shows your most recently modified notes (from the MRU
tracker) and your open tasks, with quick actions to jump somewhere else.
Call it again (or `q`) to close it. It hosts like a welcome/home screen:

* If the current window is still the empty startup buffer, Home opens **in that
  window** as a welcome screen.
* Otherwise it opens in a **new tab page** so it never interferes with what you're editing.

**Sections**

* **📌 Pinned** — notes with `pinned: true` in their frontmatter, newest first
  (up to 8). Nothing else pins a note, and the section says so when it is empty.
* **📌 Recently Modified** — from the same MRU state that powers the
  `notes_recent` MCP tool (up to 8).
* **Lanes** — `🔁 In Progress`, `📝 Todo`, `❓ Ask`, `🔖 TODO / tags`. A checklist
  card lands in a lane by its own checkbox (`[/]`/`[~]` in progress, `[ ]` todo);
  inline `TODO`/`ASK` markers and `#todo`/`#tech-debt` tags fill the last two.
  `[x]` items never become cards.
* **🚀 Quick Actions** — the key hints at the bottom of the dashboard.

**Keys**

* `<CR>` on a pinned, recent, or task row: open that note in a new split. On a
  task that carries a linked detail note (`- [ ] [[ Parent/Child ]]`), it opens
  the **detail note** instead — the board it hangs off is one hop away via the
  detail's `source_note` frontmatter or `<C-o>`.
* `p` / `x` / `b` on a lane card: promote a todo to in-progress, complete an
  in-progress task, or send one back to todo. Home rewrites just that line —
  editing an already-open buffer and saving it (so unsaved edits survive)
  rather than reading the file fresh — and stamps the linked detail note's own
  `status` frontmatter to match, the same call the `notes_toggle_task` MCP tool
  makes.
* `n`: new note · `d`: daily · `s`: search · `t`: tasks picker · `r`: refresh · `q`: close
* Sections are color-coded and icon-led (`📚` title, `📌` pinned/recent, `📝` tasks, `🚀` actions).
  Override the highlight groups `NotesHomeTitle`, `NotesHomeHeadPinned`,
  `NotesHomeHeadRecent`, `NotesHomeHeadTasks`, `NotesHomeHeadActions`,
  `NotesHomeRecentBody`, `NotesHomePinnedBody`, `NotesHomeTaskBody`,
  `NotesHomeDoingBody`, `NotesHomeAskBody`, `NotesHomeMuted` to restyle.

## 🗂️ Notes Explorer Sidebar

Toggle the sidebar with `:Notes explorer` or your bound key.

### Keymaps inside the Explorer buffer:
* `<CR>` / `o`: Open the highlighted note.
* `i`: Show details/metadata for the selected note, directory, or asset.
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

By default, every directory is expanded when the explorer opens. To start collapsed
instead, set:

```lua
require("notes").setup {
  explorer = {
    expand_all = false,
  },
}
```

---

## ✍️ Markdown Buffer-local Keymaps

When editing markdown files in your `notes_dir`, the plugin automatically activates buffer-local keymaps for fluid editing:

* **Wiki-link Jump (`<CR>`)**: Press `<CR>` while cursor is on `[[Link]]` to navigate to that note.
* **Task Toggle (`<leader>nt`)**: Toggle checklist state on the current line between `- [ ]` and `- [x]`.
* **Revision History (`<leader>nh`)**: Open Telescope revision timeline with Live Diff Previewer (`<leader>nh` in Normal mode).
* **Bold (`<leader>nb`)**: Toggle bold formatting (`**text**`) on visual selection.
* **Italic (`<leader>ni`)**: Toggle italic formatting (`*text*`) on visual selection.
* **Strikethrough (`<leader>ns`)**: Toggle strikethrough formatting (`~~text~~`) on visual selection.
* **Hyperlink (`<leader>nl`)**: Prompt for URL and insert formatted hyperlink (`[text](URL)`) on visual selection.
* **Highlight Toggle (`<leader>nh`)**: Toggle highlight formatting (`==text==`) on visual selection (Visual mode).

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

## 🤖 MCP Server (Model Context Protocol)

`notes.nvim` ships with a built-in **MCP (Model Context Protocol) server** so AI agents (e.g. CodeCompanion.nvim) can read, write, search, and manage your notes directly — without manually traversing the filesystem.

The server runs as a stdio-based JSON-RPC 2.0 process inside `nvim --headless` and uses your existing `notes.nvim` configuration (falling back to the `NOTES_DIR` environment variable, or `~/.notes`, when the plugin config is unavailable).

### Launching the server

Add the following to your MCP client configuration (e.g. CodeCompanion.nvim):

```json
{
  "mcpServers": {
    "notes": {
      "command": "nvim",
      "args": ["--headless", "-c", "lua require('notes.mcp').start()"]
    }
  }
}
```

### Exposed tools

The server registers the following tools:

| Tool | Description | Required params | Optional params |
| :--- | :--- | :--- | :--- |
| `notes_list` | List all notes with metadata (title, date, tags, summary). | — | `query`, `tag`, `limit` |
| `notes_read` | Read a note's full content/metadata. Resolves a full path, bare filename, or title; a miss returns similar paths. Returns a content `hash` for optimistic writes. | `path` | — |
| `notes_search` | Search notes by title, tags, or summary. | `query` | `tag`, `limit` |
| `notes_search_content` | Full-text search inside note content. Uses ripgrep when available, otherwise falls back to a built-in Lua search. | `query` | — |
| `notes_backlinks` | Find notes containing wiki-links to a target note. | `path` | — |
| `notes_get_metadata` | Get a note's YAML frontmatter metadata, including custom fields such as `parent`/`source_note`. | `path` | — |
| `notes_resolve_link` | Resolve a wiki-link (`[[ Parent/Child ]]`, alias, or bare body) to a note path. Returns suggestions when the link cannot be resolved. | `link` | `from_path` |
| `notes_create` | Create a note. `content` is used verbatim as the body (the template supplies frontmatter only). With `parent`, uses the task-detail convention (frontmatter `parent`/`source_note`, path `tasks/YYYY/MM/YYYY-MM-DD-<slug>.md`); with `board_path`, also inserts the matching checklist line, preferring an exact parent label over child links containing it. | `title` | `content`, `tags`, `directory`, `template`, `parent`, `source_note`, `date`, `board_path`, `heading`, `board_text`, `board_status`, `parent_match`, `parent_lnum`, `board_parent_*` |
| `notes_delete` | Delete a note or directory by path (relative or absolute). | `path` | — |
| `notes_update` | Update an existing note's content and/or frontmatter fields (title, tags, summary, date, custom fields). Omitted fields are preserved. Pass `expected_hash` to reject the write if the file changed since it was read. | `path` | `content`, `title`, `tags`, `summary`, `date`, `metadata`, `expected_hash` |
| `notes_recent` | Most recently opened/edited notes. `current` is the last-accessed note; `recent` is newest-first with path, title, date. Refreshed from your live session via the MRU state file. | — | `limit` |
| `notes_tasks` | Scan all notes for open tasks: checklist items (`- [ ]` todo, `- [/]`/`- [~]` doing, `- [?]` waiting; done excluded), inline `TODO`/`ASK` markers, and `#todo`/`#tech-debt` tags. Mirrors the Notes Home kanban board; the returned `lnum` feeds `notes_toggle_task`. | — | `type`, `status`, `limit` |
| `notes_toggle_task` | Atomically change one checklist task's status (`todo` → `- [ ]`, `doing` → `- [/]`, `waiting` → `- [?]`, `done` → `- [x]`) by rewriting only that line. `mark` accepts a raw glyph or status; identify the line by `lnum`, `match`, or wiki-`link`. Stamps a linked detail note's `status` frontmatter to match. | `path` | `status`, `mark`, `lnum`, `match`, `link`, `expected_hash` |
| `notes_add_task` | Insert one checklist line under a day `heading` and/or `parent` task without rewriting the rest of the board. Render a link with `link`. | `path` | `text`, `link`, `status`, `heading`, `day`, `parent`, `parent_lnum`, `parent_link`, `expected_hash` |
| `notes_copy_task_to_today` | Copy a checklist item into today's daily note (created if needed), resetting its box while keeping its text/wiki-link. It reuses or creates the destination parent group and nests the task under it, and replaces an empty `- [ ]` placeholder instead of leaving it above the copy. `target_path` + `target_heading` can copy between sections of the same board; duplicate detection is scoped to the destination heading. Identify the source via `from_path` + `lnum`/`match`/`link`, or just `link`. | — | `from_path`, `lnum`, `match`, `link`, `heading`, `date`, `target_path`, `target_heading`, `status`, `expected_hash` |
| `notes_append_info` | Insert a `- Info (<day>): ...` line above a note's checklist. `position='summary'` keeps it inside `## Summary` (above that section's checklist, or after its last paragraph) with a blank line before the next heading; `position='end'` appends to the note. | `path`, `text` | `label`, `day`, `position`, `expected_hash` |
| `notes_add_subtask` | Add a linked subtask under an existing checklist line: writes a detail note and inserts a nested `- [ ] [[ parent/title ]]` line beneath the parent. `detail_note_created` is `false` when a note for that exact title was reused. | `path`, `title` | `parent_lnum`, `parent_match`, `parent_link`, `heading`, `expected_hash` |
| `notes_board_status` | Roll up checklist status counts (todo/doing/waiting/done) for one note, grouped by its markdown headings — answers "what's left" on a weekly/board note without reading it. | `path` | — |
| `notes_rollover_tasks` | Create a new note carrying forward every not-done checklist item from an existing board note, keeping each item's heading and parent-task context. | `from_path`, `title` | `directory`, `tags` |
| `notes_history` | Git commit history for a note (hash, author, date, subject, lines added/removed), or vault-wide when `path` is omitted. Pass a commit's `hash` to `notes_diff`. | — | `path`, `limit` |
| `notes_diff` | Show the git diff introduced by a commit (hash from `notes_history`), optionally scoped to one note's path. | `commit` | `path` |

### Notes on behavior

- **Path resolution**: Relative paths are resolved against your `notes_dir`; absolute paths are used as-is. A bare filename or title (`w2-oct-2026.md`, `Weekly: w2 oct 2026`) is also resolved across the vault, and a miss returns `suggestions` with similar paths. `notes_resolve_link` does the same for `[[ wiki-links ]]`.
- **Optimistic writes**: `notes_read` (and `notes_create`/`notes_board_status`) return a content `hash`. Writers that accept `expected_hash` (`notes_update`, `notes_toggle_task`, `notes_add_task`, `notes_add_subtask`, `notes_append_info`, `notes_copy_task_to_today`) refuse the write with `code: "stale_note"` when the file changed since that read.
- **Templates excluded**: Files under `notes_dir/templates/` are skipped during listing and search, keeping your workspace clean.
- **Fallback dates**: Notes without a `date` in frontmatter report their file modification time.
- **Git tools need a repo**: `notes_history` and `notes_diff` read via `git -C <notes_dir>` and report an error when the notes directory is not a git work tree; the rest of the server is unaffected.
- **Protocol**: Implements MCP protocol version `2024-11-05` with `tools/list` and `tools/call` support, advertising itself as `notes-mcp` v`0.1.0`.

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

#### Custom Directories

By default, notes are saved to date-based subdirectories (`YYYY/MM/DD/title.md`). You can override this per template by specifying a `directory`:

```lua
require("notes").setup({
  notes_dir = "~/.notes",
  templates = {
    job_application = { directory = "documents/jobs/applications" },
    documentation = { directory = "docs/tech" },
    meeting = { directory = "meetings" },
  }
})
```

When set, notes from that template are saved to `<notes_dir>/<directory>/<title>.md`. The built-in template content is preserved — you only need to specify `directory`. You can also provide custom `content` alongside `directory`:

```lua
templates = {
  job_application = {
    content = [[---
title: "%TITLE%"
date: "%DATE%"
---
# %TITLE%

## Status
- [ ] Applied
]],
    directory = "documents/jobs/applications",
  }
}
```

#### Selectable Subdirectories

Use `options` when one template is shared by several projects or categories. The
selected option is shown below the title field; use `<Tab>` and `<S-Tab>` to
change it before pressing `<CR>`:

```lua
templates = {
  rfc = {
    directory = "projects/%OPTION%/rfc",
    options = { "notes.nvim", "website", "backend-api" },
    content = [[---
title: "%TITLE%"
date: "%DATE%"
tags: ["project"]
---

# %TITLE%

%BODY%
]],
  },
}
```

`%OPTION%` in `directory` is replaced by the selected value. For example,
selecting `backend-api` above creates the note at
`<notes_dir>/projects/backend-api/rfc/<title>.md`. If `directory` does not
contain `%OPTION%`, the selection is appended instead, so `directory =
"projects"` creates `<notes_dir>/projects/backend-api/<title>.md`.

Each option must be a single folder name; empty values, `.`/`..`, and values
containing `/` or `\` are ignored. A template that uses `%OPTION%` without any
valid options reports an error and does not create a note. Templates without
`options` keep the original title popup and save behavior.

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
