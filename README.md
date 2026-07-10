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
      editor_style = "current",            -- "current" (default) or "float"
      keymaps = {
        n = {
          ["<leader>nc"] = "new",          -- Create a new note
          ["<leader>nd"] = "daily",        -- Open today's daily journal
          ["<leader>nl"] = "list",         -- List notes using Telescope
          ["<leader>ne"] = "explorer",     -- Toggle the sidebar explorer
          ["<leader>ns"] = "search",       -- Live search note contents
          ["<leader>np"] = "paste_image",  -- Paste clipboard image
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
* `q`: Close the explorer sidebar.
* `?`: Show the help popup displaying all available keymaps.

---

## ✍️ Markdown Buffer-local Keymaps

When editing markdown files in your `notes_dir`, the plugin automatically activates buffer-local keymaps for fluid editing:

* **Wiki-link Jump (`<CR>`)**: Press `<CR>` while cursor is on `[[Link]]` to navigate to that note.
* **Task Toggle (`<leader>nt`)**: Toggle checklist state on the current line between `- [ ]` and `- [x]`.

---

## 📄 Configuration Options

```lua
require("notes").setup({
  notes_dir = vim.fn.expand("~/.notes"),   -- Notes workspace directory
  date_format = "%Y-%m-%d",                -- Date format used in templates
  time_format = "%H:%M:%S",                -- Time format used in templates
  length_title = 60,                       -- Char limit for note titles
  length_summary = 140,                    -- Char limit for summary frontmatter field
  editor_style = "current",                -- "current" (default) to edit in place, or "float" for floating popup/modal
  
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

  -- Bind your user commands to custom keys
  keymaps = {
    n = {
      ["<leader>nc"] = "new",
      ["<leader>nd"] = "daily",
      ["<leader>nl"] = "list",
      ["<leader>ne"] = "explorer",
      ["<leader>ns"] = "search",
      ["<leader>np"] = "paste_image",
    }
  }
})
```

---
