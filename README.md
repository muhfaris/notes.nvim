## Notes Plugin for Neovim (Under Development)

---

This plugin provides a set of functionalities for managing notes in markdown format within Neovim.

[![asciicast](https://asciinema.org/a/bp4Ke8AyXlHLSe71JJJXKRmSN.svg)](https://asciinema.org/a/bp4Ke8AyXlHLSe71JJJXKRmSN)

### Features:

- Create new notes with a pre-defined template including title, date, labels, summary, description, and conclusion.
- List existing notes grouped by creation date.
- Open a selected note for editing.
- Delete existing notes (with confirmation).
- Configurable key mappings (no default keybindings provided).
- Customizable note templates (with required `Title` and `Summary` sections).

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
          ["<leader>ac"] = "new_note",      -- Create a new note
          ["<leader>al"] = "list_notes",    -- List all notes
          ["<leader>api"] = "paste_image",  -- Paste an image into a note
        },
      },
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
  :NewNote
  ```

- **List existing notes:**

  Use your custom key mapping, e.g., `<leader>al`:

  ```
  :ListNotes
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

## Labels: %LABEL%

## Summary

## Description

%BODY%

## Conclusion
```

#### Explanation of placeholders:

- `%TITLE%`: Replaced with the title of the note.
- `%DATE%`: Replaced with the current date (formatted using `date_format`).
- `%LABEL%`: Replaced with the labels/tags (optional).
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

### Dependencies:

This plugin requires the following dependencies, which will automatically be installed when using **lazy.nvim**:

- **[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)**: Used for fuzzy finding notes.
- **[Plenary.nvim](https://github.com/nvim-lua/plenary.nvim)**: Utility functions that power various parts of the plugin.

### Disclaimer

**Note:** This plugin is currently under development. More features and functionalities might be added in the future.
