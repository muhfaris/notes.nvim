## Notes Plugin for Neovim (Under Development)

This plugin provides a set of functionalities for managing notes in markdown format within Neovim.

### Features:

- Create new notes with a pre-defined template including title, date, and sections for introduction and conclusion.
- List existing notes grouped by creation date.
- Open a selected note for editing.
- Delete existing notes (with confirmation).

### Installation (Lazy Loading):

**Using a plugin manager like packer.nvim:**

```lua
use { 'muhfaris/notes.nvim', lazy = true }
```

**Direct installation:**

1. Clone this repository or copy the code into a directory named `notes` inside your Neovim configuration directory (`~/.config/nvim/lua`).
2. In your `init.lua` file, add the following line:

```lua
require('notes').setup({
  notes_dir = "/home/muhfaris/.notes",
})
```

### Usage:

**Create a new note:**

```
:NewNote
```

**List existing notes:**

```
:ListNotes
```

**Open a listed note for editing:**

Move the cursor to the desired note in the "Notes List" buffer and press `<CR>`.

**Delete a listed note:**

Move the cursor to the desired note in the "Notes List" buffer and press `d`. (Confirmation will be prompted)

### Configuration:

The plugin comes with a default configuration but allows you to customize some aspects:

- `notes_dir`: Path to the directory where notes will be stored. (Default: `~/.notes`)
- `date_format`: Format string for the date included in the template. (Default: "%Y-%m-%d")
- `time_format`: Format string for the time included in the template. (Default: "%H:%M:%S")
- `template`: Markdown template used for creating new notes. You can customize the placeholders like `%%TITLE%%` and `%%BODY%%`.

To modify the configuration, add the following snippet to your `init.lua` file:

```lua
local notes = require('notes')

notes.setup({
  notes_dir = "/path/to/your/notes/directory",
  -- Other configuration options
})
```

## Disclaimer

**Note:** This plugin is currently under development. More features and functionalities might be added in the future.
