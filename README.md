# 🌿 eda.nvim

Explore as a tree, edit as a buffer — a file explorer for Neovim that combines hierarchical navigation with buffer-native file operations.

[![CI](https://github.com/wadackel/eda.nvim/actions/workflows/ci.yaml/badge.svg)](https://github.com/wadackel/eda.nvim/actions/workflows/ci.yaml)
![Neovim](https://img.shields.io/badge/Neovim-%3E%3D0.11-green?logo=neovim&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Demo

### Tree View

![Tree View](./docs/assets/vhs/tree-basic.png)

### Buffer Editing

![Buffer Editing](./docs/assets/vhs/buffer-edit.gif)

### Split Operation

![Split Operation](./docs/assets/vhs/split-operation.gif)

### Git Changes Filter

![Git Changes Filter](./docs/assets/vhs/git-filter.png)

### Layouts

| Split | Replace |
|-------|---------|
| ![Split](./docs/assets/vhs/layout-split.png) | ![Replace](./docs/assets/vhs/layout-replace.png) |

## Why eda.nvim?

- ✏️ **Buffer-native editing meets tree view** — Edit the buffer to rename, delete, create, and move files, then `:w` to apply. Combines oil.nvim's buffer-editing paradigm with a full collapsible tree view
- ⚡ **Progressive async rendering** — The target file's ancestor chain is scanned first, so the cursor lands instantly even in large repositories. Remaining directories load in the background
- 🧩 **Extensible action system** — Every operation lives in a named registry. Custom actions receive the same `ActionContext` as built-in ones, making them first-class citizens
- 🎨 **Rich customization** — 60+ highlight groups across 6 categories, function-based config options (`header.format`, `ignore_patterns`, `preview.max_file_size`), and event hooks for plugin integration

> For architecture and design decisions, see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Features

- **Buffer-native editing** — Rename, delete, and create files by editing the buffer, then `:w` to apply
- **Tree view with hierarchy** — Collapsible directory tree, not flat per-directory listing
- **Progressive async rendering** — Ancestor chain scanned first for instant cursor placement
- **Git integration** — Async status detection with visual indicators
- **Multiple layouts** — `float`, `split_left`, `split_right`, `replace`
- **Extensible action system** — Named registry with custom actions as first-class citizens
- **netrw replacement** — `hijack_netrw` option for seamless default browsing
- **60+ highlight groups** — Full appearance customization across 6 categories
- **Event hooks** — `EdaTreeOpen`, `EdaMutationPost`, etc. for plugin integration

## Requirements

- Neovim >= 0.11
- [git](https://git-scm.com/) (optional, for git status integration)
- [mini.icons](https://github.com/echasnovski/mini.icons) or [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for file icons)

## Installation

<details>
<summary>lazy.nvim</summary>

```lua
{
  "wadackel/eda.nvim",
  opts = {},
}
```

</details>

<details>
<summary>mini.deps</summary>

```lua
local add = MiniDeps.add
add("wadackel/eda.nvim")
require("eda").setup()
```

</details>

<details>
<summary>packer.nvim</summary>

```lua
use({
  "wadackel/eda.nvim",
  config = function()
    require("eda").setup()
  end,
})
```

</details>

## Quick Start

```lua
require("eda").setup()
```

Open the explorer with the `:Eda` command:

```vim
:Eda                    " Open in current directory (float)
:Eda kind=split_left    " Open as left sidebar
:Eda ~/projects         " Open specific directory
```

> [!TIP]
> Set `hijack_netrw = true` to use eda as the default directory browser. See the [Replace netrw](#recipes) recipe for details.

See [Configuration](#configuration) below for all options, or `:help eda.nvim` for the full reference.

## Configuration

Below are all available options with their default values. You only need to specify the options you want to change — everything is deep-merged with the defaults.

```lua
require("eda").setup({
  -- Markers used to detect the project root
  root_markers = { ".git", ".hg" },
  -- Show hidden/dotfiles by default
  show_hidden = true,
  -- Show git-ignored files by default
  show_gitignored = true,
  -- Show only files with git changes (toggle via `gs`, default off)
  show_only_git_changes = false,
  -- Lua patterns matched against file/directory name (not glob)
  -- Accepts a function: fun(root_path): string[]
  ignore_patterns = {},

  window = {
    -- Layout: "float", "split_left", "split_right", "replace"
    kind = "float",
    -- Border style (see :help nvim_open_win)
    border = "rounded",
    -- Per-kind window dimensions (string percentage or number or function)
    kinds = {
      float = { width = "94%", height = "80%" },
      replace = {},
      split_left = { width = "30%" },
      split_right = { width = "30%" },
    },
    -- Buffer-local options applied to the eda buffer
    buf_opts = {
      filetype = "eda",
      buftype = "acwrite",
    },
    -- Window-local options applied to the eda window
    win_opts = {
      number = false,
      relativenumber = false,
      wrap = false,
      signcolumn = "no",
      cursorline = true,
      foldcolumn = "0",
    },
  },

  -- Use eda as the default directory browser (replaces netrw)
  hijack_netrw = false,
  -- Close explorer window after selecting a file
  close_on_select = false,

  -- Confirmation dialogs (boolean or table; true = all defaults below)
  confirm = {
    -- Confirm before deleting files
    delete = true,
    -- Confirm moves: true, false, or "overwrite_only"
    move = "overwrite_only",
    -- Confirm creation: true, false, or integer (threshold count)
    create = false,
    -- Path display in confirm dialogs: "full", "short", "minimal", or fun(path, root_path): string
    path_format = "short",
    -- Signs shown in confirm dialogs
    signs = {
      create = "",
      delete = "",
      move = "",
    },
  },

  -- Use trash instead of permanent delete
  delete_to_trash = true,
  -- Follow symbolic links when scanning
  follow_symlinks = true,
  -- Directories with more entries than this skip sorting for performance
  large_dir_threshold = 5000,
  -- Maximum depth for initial directory expansion
  expand_depth = 5,

  -- Automatically reveal the focused file in the tree
  update_focused_file = {
    -- Enable auto-reveal
    enable = false,
    -- Also change the tree root to the file's project root
    update_root = false,
  },

  icon = {
    -- Separator between icon and file name
    separator = " ",
    -- Icon provider: "mini_icons", "nvim_web_devicons", or "none"
    provider = "mini_icons",
    -- Directory glyphs keyed by open/empty state
    directory = {
      collapsed = "󰉋",
      expanded = "󰝰",
      empty = "󰉖",
      empty_open = "󰷏",
    },
    -- Optional hook to override icons per node. Returning nil falls through
    -- to the built-in directory glyphs and the provider lookup.
    -- See `doc/eda.md` for full reference.
    --
    -- custom = function(name, node)
    --   if name == "justfile" then return "󱃔", "EdaFileIcon" end
    --   return nil
    -- end,
    custom = nil,
  },

  git = {
    -- Enable git status integration
    enabled = true,
    -- Git status icons
    icons = {
      untracked = "",
      added = "",
      modified = "●",
      deleted = "",
      renamed = "",
      staged = "",
      conflict = "",
      ignored = "◌",
    },
  },

  indent = {
    -- Indentation width per nesting level
    width = 2,
  },

  preview = {
    -- Enable file preview panel
    enabled = false,
    -- Debounce delay in milliseconds before showing preview
    debounce = 100,
    -- Maximum file size in bytes to preview (also accepts fun(path): integer)
    max_file_size = 102400,
  },

  -- Show full filename in a floating window when truncated in narrow windows
  full_name = {
    -- Enable floating window for truncated filenames
    enabled = true,
  },

  -- Header displayed above the tree (set to false to disable entirely)
  header = {
    -- Format: "short", or fun(root_path): string|false
    format = "short",
    -- Position: "left", "center", "right"
    position = "left",
    -- Show a divider line below the header
    divider = false,
  },

  -- Set default_mappings = false to clear all defaults before applying yours
  -- Key mappings: string = built-in action, function = custom, false = disable
  mappings = {
    ["<CR>"] = "select",              -- Open file or toggle directory
    ["<2-LeftMouse>"] = "select",     -- Open file or toggle directory
    ["<C-t>"] = "select_tab",        -- Open file in new tab
    ["|"] = "select_vsplit",          -- Open file in vertical split
    ["-"] = "select_split",           -- Open file in horizontal split
    ["q"] = "close",                  -- Close explorer
    ["^"] = "parent",                 -- Navigate to parent directory
    ["~"] = "cwd",                    -- Change root to cwd
    ["gC"] = "cd",                    -- Change root to directory
    ["W"] = "collapse_recursive",     -- Collapse directory recursively
    ["E"] = "expand_recursive",       -- Expand directory recursively
    ["gW"] = "collapse_all",          -- Collapse all directories
    ["gE"] = "expand_all",            -- Expand all directories
    ["yp"] = "yank_path",            -- Yank relative path
    ["yP"] = "yank_path_absolute",   -- Yank absolute path
    ["yn"] = "yank_name",            -- Yank file name
    ["<C-l>"] = "refresh",           -- Refresh file tree
    ["<C-h>"] = "collapse_node",     -- Collapse node or go to parent
    ["g."] = "toggle_hidden",         -- Toggle hidden files
    ["gi"] = "toggle_gitignored",    -- Toggle gitignored files
    ["gs"] = "toggle_git_changes",   -- Toggle git-changes filter
    ["[c"] = "prev_git_change",      -- Jump to previous git change
    ["]c"] = "next_git_change",      -- Jump to next git change
    ["m"] = "mark_toggle",           -- Toggle mark on node
    ["D"] = "mark_bulk_delete",      -- Delete marked nodes
    ["go"] = "system_open",          -- Open with system application
    ["K"] = "inspect",               -- Inspect node data
    ["gd"] = "duplicate",            -- Duplicate file
    ["gx"] = "cut",                  -- Cut selected nodes
    ["gy"] = "copy",                 -- Copy selected nodes
    ["gp"] = "paste",                -- Paste from register
    ["g?"] = "help",                 -- Show keymap help
    ["ga"] = "actions",              -- Open action picker
    ["<C-f>"] = "preview_scroll_down", -- Scroll preview down (half page)
    ["<C-b>"] = "preview_scroll_up",   -- Scroll preview up (half page)
    ["<C-w>v"] = "split",            -- Open split pane
    ["<C-w>s"] = "vsplit",           -- Open horizontal split pane
  },

  -- Callback to customize highlight groups: fun(groups: table)
  on_highlight = nil,
  -- Window picker function for file selection: fun(): integer?
  select_window = nil,
})
```

> [!TIP]
> See `:help eda.nvim` for detailed descriptions of each option, available actions, events, and highlight groups.

## Recipes

Common customization patterns. See `:help eda.nvim` for the full configuration reference.

<details>
<summary>Replace netrw</summary>

Use eda.nvim as the default directory browser. `:edit <directory>`, `:Explore`, and other netrw entry points will open eda instead.

```lua
require("eda").setup({
  hijack_netrw = true,
})
```

</details>

<details>
<summary>LSP file operations</summary>

Notify language servers when files are renamed or moved via the `EdaMutationPost` event. Works with [nvim-lsp-file-operations](https://github.com/antosha417/nvim-lsp-file-operations) or a manual handler.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "EdaMutationPost",
  callback = function(ev)
    -- ev.data.operations contains { type, src, dst } entries
    -- ev.data.results contains the operation outcomes
    local ok, lsp_ops = pcall(require, "lsp-file-operations")
    if ok then
      lsp_ops.did_rename(ev.data.operations)
    end
  end,
})
```

</details>

<details>
<summary>Window picker integration</summary>

Use [nvim-window-picker](https://github.com/s1n7ax/nvim-window-picker) (or any picker that returns a window ID) to choose where files open.

```lua
require("eda").setup({
  select_window = function()
    return require("window-picker").pick_window()
  end,
})
```

</details>

<details>
<summary>Custom header with git branch</summary>

Show the current git branch in the header instead of the directory path.

```lua
require("eda").setup({
  header = {
    format = function(root_path)
      local result = vim.system(
        { "git", "-C", root_path, "branch", "--show-current" },
        { text = true }
      ):wait()
      if result.code == 0 and result.stdout ~= "" then
        return result.stdout:gsub("\n", "")
      end
      return vim.fn.fnamemodify(root_path, ":~")
    end,
    position = "left",
  },
})
```

</details>

<details>
<summary>Project-aware ignore patterns</summary>

Dynamically filter files based on project type. Patterns use **Lua pattern syntax** (not glob).

```lua
require("eda").setup({
  ignore_patterns = function(root_path)
    local patterns = { "%.DS_Store$" }
    if vim.uv.fs_stat(root_path .. "/package.json") then
      table.insert(patterns, "^node_modules$")
    end
    if vim.uv.fs_stat(root_path .. "/Cargo.toml") then
      table.insert(patterns, "^target$")
    end
    return patterns
  end,
})
```

</details>

<details>
<summary>Customize highlights</summary>

Override highlight groups to match your colorscheme. The `on_highlight` callback receives the groups table before it is applied — modify entries in-place.

```lua
require("eda").setup({
  on_highlight = function(groups)
    groups.EdaDirectoryName = { fg = "#89b4fa", bold = true }
    groups.EdaDirectoryIcon = { fg = "#89b4fa" }
    -- Apply git status colors to file names (transparent by default)
    groups.EdaGitModifiedName = { link = "EdaGitModified" }
    groups.EdaGitAddedName = { link = "EdaGitAdded" }
  end,
})
```

</details>

<details>
<summary>Customize icons</summary>

Combine `icon.provider`, `icon.directory`, and the `icon.custom` hook to fully control every icon. This example builds a minimal UI with plain Unicode characters — no Nerd Font required.

```lua
require("eda").setup({
  icon = {
    provider = "none",
    directory = {
      collapsed = "▸",
      expanded = "▾",
      empty = "▸",
      empty_open = "▾",
    },
    custom = function(name, node)
      if node.type == "directory" then
        return nil
      end
      return "·", "EdaFileIcon"
    end,
  },
})
```

</details>

<details>
<summary>Register custom actions</summary>

Add project-specific actions to the registry. They appear in the action picker (`ga`) and can be mapped to keys.

```lua
local action = require("eda.action")

action.register("open_terminal", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  local dir = node and node.is_dir and node.path
    or node and vim.fn.fnamemodify(node.path, ":h")
    or ctx.explorer.root_path
  vim.cmd("split | terminal")
  vim.fn.chansend(vim.b.terminal_job_id, "cd " .. vim.fn.shellescape(dir) .. "\n")
end, { desc = "Open terminal in directory" })

-- Map it
require("eda").setup({
  mappings = {
    ["<C-\\>"] = "open_terminal",
  },
})
```

</details>

## Documentation

- `:help eda.nvim` — Full reference (configuration, actions, API, events, highlights)
- [CHANGELOG.md](CHANGELOG.md) — Release history
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Architecture, design philosophy, and trade-offs
- [CONTRIBUTING.md](CONTRIBUTING.md) — Development setup and guidelines

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

## License

[MIT © wadackel](LICENSE)
