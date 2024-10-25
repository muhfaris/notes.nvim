## Notes Plugin for Neovim (Under Development)

---

This plugin provides a set of functionalities for managing notes in markdown format within Neovim.

![note-demo](https://github.com/user-attachments/assets/62c4bfaa-5a9b-459a-ab5a-06bae2d8c1c8)

### Features:

- Create new notes with a pre-defined template including title, date, labels, summary, description, and conclusion.
- List existing notes grouped by creation date.
- Open a selected note for editing.
- Delete existing notes (with confirmation).
- Configurable key mappings (no default keybindings provided).
- Customizable note templates (with required `Title` and `Summary` sections).
- Find notes using [Telescope](https://github.com/nvim-telescope/telescope.nvim)
  fuzzy finder by keyword.

### Installation (Lazy Loading with `lazy.nvim`):

To install the plugin using **lazy.nvim**, add the following to your `lazy` setup:

```lua
return {
  "muhfaris/notes.nvim",
  config = function()
    require("notes").setup {
      notes_dir = "/home/muhfaris/.notes",  -- Specify your notes directory
      keymaps = {                          -- Configure your custom key mappings
        n = {
          ["<leader>nc"] = "new",      -- Create a new note
          ["<leader>nl"] = "list",    -- List all notes
          ["<leader>npi"] = "paste_image",  -- Paste an image into a note
          ["<leader>nfk"] = "find_by_keyword", -- Find notes by keyword
        },
      },
      length_title = 50,                    -- Maximum length of the title
      length_summary = 90,                   -- Maximum length of the summary
    }
  end,
  dependencies = {
    "nvim-telescope/telescope.nvim",       -- Telescope integration for fuzzy finding notes
    "nvim-lua/plenary.nvim",               -- Utility functions required by the plugin
  },
}
```

### Usage:

Since the plugin does not come with default key mappings, you must define them in your setup as shown in the configuration above.

#### Example Key Mapping Usage:

- **Create a new note:**

  Use your custom key mapping, e.g., `<leader>ac`:

  ```
  :Notes new
  ```

- **List existing notes:**

  Use your custom key mapping, e.g., `<leader>al`:

  ```
  :Notes list
  ```

- **Find notes by keyword:**

  Use your custom key mapping, e.g., `<leader>afk`:

  ```
  :Notes find_by_keyword
  ```

- **Paste an image into a note:**

  Move the cursor to the desired note in the "Notes List" buffer and press `<Ctrl+p>` to paste an image into the note.

  ```
  :Notes paste_image
  ```

- **Open a listed note for editing:**

  Move the cursor to the desired note in the "Notes List" buffer and press `<CR>`.

- **Delete a listed note:**

  Select the note you want to delete and press `<Ctrl+d>` to confirm.

### Default Note Template:

When creating a new note, the following default template is used:

```markdown
# Title: %TITLE%

## Date: %DATE%

## Keywords: %Keywords%

## Summary

## Description

%BODY%

## Conclusion
```

#### Explanation of placeholders:

- `%TITLE%`: Replaced with the title of the note.
- `%DATE%`: Replaced with the current date (formatted using `date_format`).
- `%Keywords%`: Replaced with the labels/tags (optional, example value: `tag1, tag2`).
- `%BODY%`: Placeholder for the main content of the note.

### Customizing the Template:

You can customize the note template by providing your own template configuration. However, **the `Title` and `Summary` sections are required** and must be included in any custom template. This ensures that key metadata is always captured in the notes.

#### Example of Custom Template:

```lua
require('notes').setup({
  notes_dir = "/path/to/your/notes/directory",
  template = [[
  # Title: %TITLE%

  ## Date: %DATE%

  ## Summary

  %BODY%

  ## Additional Info

  ]],
})
```

In this example, the `Summary` section is retained and required, while the `Description` and `Labels` sections are removed.

#### Configuration Options:

- `notes_dir`: Path to the directory where notes will be stored. (Default: `~/.notes`)
- `date_format`: Format string for the date included in the template. (Default: "%Y-%m-%d")
- `time_format`: Format string for the time included in the template. (Default: "%H:%M:%S")
- `template`: Markdown template used for creating new notes. Must include `Title` and `Summary` sections.
- `keymaps`: Custom key mappings for the plugin commands.
- `length_title`: Maximum length of the title.
- `length_summary`: Maximum length of the summary.

### Dependencies:

This plugin requires the following dependencies, which will automatically be installed when using **lazy.nvim**:

- **[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)**: Used for fuzzy finding notes.
- **[Plenary.nvim](https://github.com/nvim-lua/plenary.nvim)**: Utility functions that power various parts of the plugin.

### Disclaimer

**Note:** This plugin is currently under development. More features and functionalities might be added in the future.

## Support

If you like this project and want to support its development, consider buying me a coffee:

[![Support via PayPal](https://img.shields.io/badge/PayPal-Support%20Me-blue.svg?logo=paypal)](https://www.paypal.com/paypalme/farisafif)
