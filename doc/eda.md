# eda.nvim

Tree-view file explorer for Neovim with buffer-native editing.

## Configuration

### Default Configuration

```lua
require("eda").setup({
  root_markers = { ".git", ".hg" },
  show_hidden = true,
  show_gitignored = true,
  show_only_git_changes = false,
  ignore_patterns = {},

  window = {
    kind = "float",
    border = "rounded",
    kinds = {
      float = { width = "94%", height = "80%" },
      replace = {},
      split_left = { width = "30%" },
      split_right = { width = "30%" },
    },
    buf_opts = {
      filetype = "eda",
      buftype = "acwrite",
    },
    win_opts = {
      number = false,
      relativenumber = false,
      wrap = false,
      signcolumn = "no",
      cursorline = true,
      foldcolumn = "0",
    },
  },

  hijack_netrw = false,
  close_on_select = false,
  confirm = true,
  delete_to_trash = true,
  follow_symlinks = true,
  large_dir_threshold = 5000,
  expand_depth = 5,

  update_focused_file = {
    enable = false,
    update_root = false,
  },

  icon = {
    separator = " ",
    provider = "mini_icons",
    directory = {
      collapsed = "󰉋",
      expanded = "󰝰",
      empty = "󰉖",
      empty_open = "󰷏",
    },
    custom = nil,
  },

  git = {
    enabled = true,
    icons = {
      untracked = "",     -- U+F420
      added = "",             -- U+F44D
      modified = "",          -- U+F444
      deleted = "",   -- U+F474
      renamed = "",    -- U+F432
      staged = "",           -- U+F42E
      conflict = "",         -- U+F421
      ignored = "◌",                     -- U+25CC
    },
  },

  indent = {
    width = 2,
  },

  preview = {
    enabled = false,
    debounce = 100,
    max_file_size = 102400,
  },

  full_name = {
    enabled = true,
  },

  mark = {
    icon = "󰄲",        -- nf-md-checkbox_marked (U+F0132)
  },

  header = {
    format = "short",
    position = "left",
    divider = false,
  },

  mappings = {
    ["<CR>"] = "select",
    ["<2-LeftMouse>"] = "select",
    ["<C-t>"] = "select_tab",
    ["|"] = "select_vsplit",
    ["-"] = "select_split",
    ["q"] = "close",
    ["^"] = "parent",
    ["~"] = "cwd",
    ["gC"] = "cd",
    ["W"] = "collapse_recursive",
    ["E"] = "expand_recursive",
    ["gW"] = "collapse_all",
    ["gE"] = "expand_all",
    ["yp"] = "yank_path",
    ["yP"] = "yank_path_absolute",
    ["yn"] = "yank_name",
    ["<C-l>"] = "refresh",
    ["<C-h>"] = "collapse_node",
    ["g."] = "toggle_hidden",
    ["gi"] = "toggle_gitignored",
    ["gs"] = "toggle_git_changes",
    ["[c"] = "prev_git_change",
    ["]c"] = "next_git_change",
    ["m"] = "mark_toggle",
    ["D"] = "delete",
    ["go"] = "system_open",
    ["K"] = "inspect",
    ["gd"] = "duplicate",
    ["gx"] = "cut",
    ["gy"] = "copy",
    ["gp"] = "paste",
    ["g?"] = "help",
    ["ga"] = "actions",
    ["<C-f>"] = "preview_scroll_down",
    ["<C-b>"] = "preview_scroll_up",
    ["<C-w>v"] = "split",
    ["<C-w>s"] = "vsplit",
  },

  on_highlight = nil,
  select_window = nil,
})
```

### root_markers

`string[]` (default: `{ ".git", ".hg" }`)

Markers used to detect the project root directory. When opening the explorer,
eda.nvim walks up from the current buffer's directory and uses the first
directory containing one of these markers as the root.

### show_hidden

`boolean` (default: `true`)

Whether to show hidden files (dotfiles) by default. Toggle at runtime with
the `toggle_hidden` action.

### show_gitignored

`boolean` (default: `true`)

Whether to show git-ignored files by default. When set to `false`, the `.git`
directory and its contents are also hidden. Toggle at runtime with the
`toggle_gitignored` action.

### show_only_git_changes

`boolean` (default: `false`)

When `true`, the tree is filtered to show only files with git changes (status
codes `M`, `A`, `D`, `R`, `C`, `?`, `U`). Ancestor directories of changed files
are kept so the tree structure is preserved, and those ancestors are
force-expanded automatically so changed files are reachable even if the dirs
were manually collapsed. The collapse state is restored when the filter is
turned off. Toggle at runtime with the `toggle_git_changes` action (default
mapping `gs`). Requires `git.enabled = true`.

While the filter is active, a `git changes` indicator is shown at the right
edge of the header row (for `split_left`, `split_right`, and `replace` window
kinds with `header` enabled) or within the float window title (for the `float`
kind). When the filter matches no files in a ready git repository, the buffer
shows `No git changes` instead of an empty tree. Opening an explorer in a
directory that is not a git repository with this option preset to `true`
automatically disables the filter and emits a warning notification.

### ignore_patterns

`string[]|fun(root_path: string): string[]` (default: `{}`)

List of Lua patterns. Files and directories whose **name** matches any pattern
are always hidden regardless of `show_hidden`. Also accepts a function that
receives the root path and returns a pattern list.

**IMPORTANT**: Patterns use **Lua pattern syntax**, not glob. For example,
`"*.log"` does NOT work. Use `"%.log$"` instead.

```lua
-- Static patterns (Lua pattern syntax)
ignore_patterns = { "%.log$", "^node_modules$", "%.o$" },

-- Dynamic patterns based on root directory
ignore_patterns = function(root_path)
  local patterns = { "%.log$" }
  if vim.uv.fs_stat(root_path .. "/package.json") then
    table.insert(patterns, "^node_modules$")
  end
  return patterns
end,
```

### window

`table`

Window layout configuration.

- `window.kind` `string` (default: `"float"`)
  Initial window layout kind. One of `"float"`, `"split_left"`,
  `"split_right"`, or `"replace"`.

- `window.border` `string` (default: `"rounded"`)
  Border style for float windows. See `:help nvim_open_win()`.

- `window.kinds` `table`
  Per-kind dimension settings. Each dimension value accepts a percentage string,
  a number, or a function returning a number (`string|number|fun(): number`):
  - `float`: `{ width = "94%", height = "80%" }`
  - `replace`: `{}`
  - `split_left`: `{ width = "30%" }`
  - `split_right`: `{ width = "30%" }`

  ```lua
  -- Function example: responsive width
  window = {
    kinds = {
      split_left = {
        width = function()
          return math.max(30, math.floor(vim.o.columns * 0.25))
        end,
      },
    },
  },
  ```

- `window.buf_opts` `table`
  Buffer-local options applied to the explorer buffer.
  Default: `{ filetype = "eda", buftype = "acwrite" }`

- `window.win_opts` `table`
  Window-local options applied to the explorer window.
  Default: `{ number = false, relativenumber = false, wrap = false, signcolumn = "no", cursorline = true, foldcolumn = "0" }`

### hijack_netrw

`boolean` (default: `false`)

When enabled, `:edit <directory>` opens eda.nvim instead of netrw.

### close_on_select

`boolean` (default: `false`)

Close the explorer window after selecting a file. Float windows always close
on selection regardless of this setting.

### confirm

`boolean|table` (default: `true`)

Controls confirmation dialogs for file operations. Accepts a boolean shorthand
or a granular table.

Boolean shorthand:
- `true` normalizes to `{ delete = true, move = "overwrite_only", create = false, path_format = "short", signs = { ... } }`
- `false` normalizes to `{ delete = false, move = false, create = false, path_format = "short", signs = { ... } }`

Granular table fields:
- `delete` `boolean` - Confirm all deletions.
- `move` `boolean|"overwrite_only"` - `true` confirms all moves, `"overwrite_only"`
  confirms only when the destination already exists.
- `create` `boolean|integer` - `true` always confirms, `false` never confirms, an
  integer N confirms when creating more than N files at once.
- `path_format` `"full"|"short"|"minimal"|function` (default: `"short"`) - Controls
  how file paths are displayed in the confirmation dialog.
  - `"full"` - Absolute paths (e.g., `/Users/me/project/src/foo.lua`)
  - `"short"` - Relative to root (e.g., `src/foo.lua`)
  - `"minimal"` - Intermediate dirs shortened to first char (e.g., `s/foo.lua`)
  - `function(path, root_path)` - Custom formatting function

  For MOVE operations, the destination path abbreviates the common directory
  prefix shared with the source using `...` (e.g., `src/core/foo.lua → .../bar.lua`).
- `signs` `table` - Nerd Font icons shown next to each operation in the
  confirmation dialog. Defaults match the corresponding `git.icons` values.
  - `create` `string` (default: `git.icons.added`) - Sign for file/directory creation
  - `delete` `string` (default: `git.icons.deleted`) - Sign for file/directory deletion
  - `move` `string` (default: `git.icons.renamed`) - Sign for file/directory move/rename

### delete_to_trash

`boolean` (default: `true`)

Send deleted files to the system trash instead of permanently removing them.

### follow_symlinks

`boolean` (default: `true`)

Follow symbolic link targets when scanning directories.

Symlink entries display a `→ <relative_path>` suffix showing the resolved
target path relative to the tree root. The `EdaSymlink` highlight (underline)
is always composed alongside any decorator highlights (e.g., git status colors).
Broken symlinks show `EdaBrokenSymlink` highlight but no target suffix.

### large_dir_threshold

`integer` (default: `5000`)

When a directory contains more entries than this threshold, eda.nvim shows
a warning before scanning.

### expand_depth

`integer` (default: `5`)

Maximum recursion depth for `expand_all` and `expand_recursive` actions.

### update_focused_file

`table`

- `enable` `boolean` (default: `false`)
  When enabled, the tree automatically reveals and highlights the file in the
  current buffer.

- `update_root` `boolean` (default: `false`)
  When enabled alongside `enable`, the tree root follows the active buffer's
  project (detected via `root_markers`).

### icon

`table`

- `separator` `string` (default: `" "`)
  String between the icon and the filename.

- `provider` `string` (default: `"mini_icons"`)
  Icon provider. One of `"mini_icons"`, `"nvim_web_devicons"`, or `"none"`.
  No fallback is attempted: if the configured provider is not installed, file icons are not displayed. Set to `"none"` to explicitly disable file icons.

- `directory` `table` - Glyphs used for directory rows based on open/empty state:
  - `collapsed` - closed directory with known or unloaded children.
  - `expanded` - open directory with children.
  - `empty` - closed directory whose contents are loaded and empty.
  - `empty_open` - open directory whose contents are loaded and empty.

- `custom` `fun(name: string, node: eda.TreeNode): (string?, string?)?` (default: `nil`)
  Override hook that returns a custom icon (and optional highlight group) for any
  node. Runs before the built-in directory glyphs and the provider lookup, so
  returning a non-nil first value wins for that node. Returning `nil` falls through
  to the default resolution.

  - `name` is a shorthand for `node.name`; use whichever is more convenient.
  - The hook runs once per visible node per repaint. Keep it cheap — no file I/O,
    no heavy pattern matching.
  - Errors are not caught: an exception propagates through the redraw callback and
    is surfaced via `:messages`. If the tree renders incorrectly after enabling
    `custom`, check `:messages` first.
  - To apply only to files, early-return on directories:
    ```lua
    custom = function(_name, node)
      if node.type == "directory" then return nil end
      -- ...
    end
    ```

  Example:
  ```lua
  icon = {
    provider = "mini_icons",
    custom = function(name, node)
      if name == "justfile" or name == "Justfile" then
        return "󱃔", "EdaFileIcon"
      end
      if node.type == "directory" and name == ".github" then
        return "", "EdaDirectoryIcon"
      end
      return nil
    end,
  }
  ```

### git

`table`

- `enabled` `boolean` (default: `true`)
  Enable asynchronous git status detection and display.

- `icons` `table` - Git status icons:
  - `untracked`, `added`, `modified`, `deleted`, `renamed`, `staged`,
    `conflict`, `ignored`

### indent

`table`

- `width` `integer` (default: `2`)
  Number of spaces per indentation level in the tree.

### preview

`table`

- `enabled` `boolean` (default: `false`)
  Enable the file preview pane.

- `debounce` `integer` (default: `100`)
  Debounce time in milliseconds before updating the preview.

- `max_file_size` `integer|fun(path: string): integer` (default: `102400`)
  Maximum file size in bytes for preview. Larger files are skipped. Accepts a
  function that receives the file path and returns a size limit.

  ```lua
  -- Allow larger previews for text files
  preview = {
    enabled = true,
    max_file_size = function(path)
      if path:match("%.md$") or path:match("%.txt$") then
        return 1024 * 500 -- 500KB for text files
      end
      return 1024 * 100 -- 100KB default
    end,
  },
  ```

### full_name

`table`

- `enabled` `boolean` (default: `true`)
  Show a floating window overlaying the cursor line when a filename is truncated
  in a narrow window. The popup displays the full line content (indent, icon,
  filename, and suffixes) with identical highlights.

### mark

`table`

- `icon` `string` (default: nf-md-checkbox_marked, U+F0132)
  Prefix marker icon displayed before the file/folder icon on marked nodes.
  Set to `""` to disable the prefix icon (the name highlight still applies).

### quickfix

`table`

- `auto_open` `boolean` (default: `true`)
  Open the quickfix window automatically after the `quickfix` action populates
  the list. Set to `false` to populate the list silently; you can open the
  window manually with `:copen`.

  When the explorer is a float (`window.kind = "float"`) and `auto_open` is
  `true`, the float is closed just before `:copen` so the quickfix window
  becomes the sole foreground pane. Split and replace layouts do not overlap
  the quickfix split and stay open.

To remove the default `gq` mapping entirely, set
`mappings = { ["gq"] = false }`.

### header

`table|false`

Set to `false` to disable the header entirely.

- `format` `string|function` (default: `"short"`)
  Header display format. Pass a string like `"short"` or a function
  `fun(root_path: string): string` for custom formatting.

- `position` `string` (default: `"left"`)
  Header text alignment. One of `"left"`, `"center"`, or `"right"`.

- `divider` `boolean` (default: `false`)
  Show a divider line below the header.

### mappings

`table<string, string|function|false|table>`

Key-to-action mappings for the explorer buffer. Values can be:
- A string action name (e.g., `"select"`)
- A function receiving `eda.PublicContext`
- `false` to disable a default mapping
- A table with `action` and optional `desc` fields

Set `default_mappings = false` in the config to clear all default mappings
before applying your custom ones.

#### Table-form Mappings

Use table-form mappings to provide a `desc` for the keymap (shown in
`vim.keymap.set` description and the help float):

```lua
mappings = {
  ["<CR>"] = { action = "select", desc = "Open file" },
  ["t"] = { action = function(ctx)
    vim.notify("CWD: " .. ctx.get_cwd())
  end, desc = "Show CWD" },
}
```

#### PublicContext

Custom function mappings receive an `eda.PublicContext` table with the
following methods:

- `get_node()` — Returns the `eda.TreeNode` under the cursor, or `nil`.
- `get_root()` — Returns the root `eda.TreeNode`.
- `get_cwd()` — Returns the explorer's root directory path.
- `get_config()` — Returns the current `eda.Config`.
- `refresh()` — Re-render the explorer buffer.

### on_highlight

`fun(groups: table)?` (default: `nil`)

Callback to customize highlight groups. Receives the highlight groups table
before it is applied. Modify entries in-place to override defaults.

```lua
require("eda").setup({
  on_highlight = function(groups)
    groups.EdaDirectoryName = { fg = "#89b4fa", bold = true }
  end,
})
```

### select_window

`fun(): integer?` (default: `nil`)

Custom window selector function. When set, eda.nvim calls this function to
determine which window to open files in. Return a window ID or `nil` to use
the default behavior.

## Commands

### `:Eda`

```
:Eda [dir] [kind=split_left]
```

Open the eda file explorer. Accepts an optional directory path and an optional
`kind` parameter to specify the window layout. Available kinds: `float`,
`split_left`, `split_right`, `replace`.

This command is defined in `plugin/eda.lua` and is available immediately after
the plugin loads, without requiring `setup()`.

Examples:
```vim
:Eda
:Eda ~/projects
:Eda kind=float
:Eda ~/projects kind=split_right
```

## Buffer Editing

eda.nvim uses a buffer-native editing model. The explorer buffer is a regular
Vim buffer — you edit it like any other buffer, then `:w` to apply changes to
the filesystem.

**Rename** — Change the text of a filename. The line's concealed node ID
tracks which file you are renaming.

**Delete** — Remove a line to delete the corresponding file or directory.
Collapsed subtrees are excluded from the diff, so files hidden under a
collapsed directory are safe.

**Create** — Add a new line with a name. Append `/` to create a directory
instead of a file.

**Move** — Change the indentation of a line to move it under a different
parent directory.

When you write the buffer (`:w`), eda.nvim computes a diff between the current
buffer state and the last rendered snapshot. Operations are grouped and
executed in order: creates (parents before children), deletes (children before
parents), and moves.

Invalidated extmarks (e.g., from external formatters mangling lines) are
skipped during parsing. The computed operations are then validated for
structural errors — missing rename targets, duplicate destinations — and
rejected on failure.

## Mappings

Default key mappings in the explorer buffer. Customize via the `mappings`
configuration option.

| Key     | Action             | Description                   |
|---------|--------------------|-------------------------------|
| `<CR>`          | select             | Open file or toggle directory |
| `<2-LeftMouse>` | select             | Open file or toggle directory |
| `<C-t>`         | select_tab         | Open in new tab               |
| `\|`    | select_vsplit      | Open in vertical split        |
| `-`     | select_split       | Open in horizontal split      |
| `q`     | close              | Close explorer                |
| `^`     | parent             | Navigate to parent directory  |
| `~`     | cwd                | Go to current working dir     |
| `gC`    | cd                 | Change root to directory      |
| `W`     | collapse_recursive | Collapse directory recursively|
| `E`     | expand_recursive   | Expand directory recursively  |
| `gW`    | collapse_all       | Collapse all directories      |
| `gE`    | expand_all         | Expand all directories        |
| `yp`    | yank_path          | Yank relative path            |
| `yP`    | yank_path_absolute | Yank absolute path            |
| `yn`    | yank_name          | Yank filename                 |
| `<C-l>` | refresh            | Refresh explorer              |
| `<C-h>` | collapse_node      | Collapse or move to parent    |
| `g.`    | toggle_hidden      | Toggle hidden files           |
| `gi`    | toggle_gitignored  | Toggle gitignored files       |
| `gs`    | toggle_git_changes | Toggle git-changes filter     |
| `[c`    | prev_git_change    | Jump to previous git change   |
| `]c`    | next_git_change    | Jump to next git change       |
| `m`     | mark_toggle        | Mark/unmark node (Visual selection or cursor) |
| `M`     | mark_clear_all     | Clear all marks               |
| `D`     | delete             | Delete target nodes (Visual > marks > cursor) |
| `go`    | system_open        | Open with system default app  |
| `K`     | inspect            | Print node details            |
| `gd`    | duplicate          | Duplicate target nodes (Visual > marks > cursor) |
| `gx`    | cut                | Cut target nodes (Visual > marks > cursor) |
| `gy`    | copy               | Copy target nodes (Visual > marks > cursor) |
| `gp`    | paste              | Paste from register           |
| `gq`    | quickfix           | Send target nodes to quickfix (Visual > marks > cursor) |
| `g?`    | help               | Show help                     |
| `ga`    | actions            | Open action picker            |
| `<C-f>` | preview_scroll_down| Scroll preview down (half page) |
| `<C-b>` | preview_scroll_up  | Scroll preview up (half page)   |
| `<C-w>v`| split              | Open explorer in vertical split |
| `<C-w>s`| vsplit             | Open explorer in horizontal split |

## Actions

All operations are registered as named actions in the action registry. Actions
can be mapped to keys, dispatched programmatically, or discovered via the
`actions` picker (`ga`).

### Navigation

- **select** — Open file in the target window or toggle directory open/closed.
- **select_split** — Open file in a horizontal split.
- **select_vsplit** — Open file in a vertical split.
- **select_tab** — Open file in a new tab.
- **parent** — Navigate to the parent directory. On the root node, changes the
  root to the parent directory.
- **cwd** — Change root to the current working directory.
- **cd** — Change root to the directory under the cursor.

### Tree Manipulation

- **collapse_all** — Collapse all directories except root.
- **collapse_node** — Collapse the current directory, or move cursor to the
  parent if already collapsed.
- **collapse_recursive** — Recursively collapse a directory and all its
  children.
- **expand_all** — Expand a directory and all children up to `expand_depth`.
- **expand_recursive** — Recursively expand a directory up to `expand_depth`.

### Yank

- **yank_path** — Yank the relative path to the system clipboard.
- **yank_path_absolute** — Yank the absolute path to the system clipboard.
- **yank_name** — Yank the filename to the system clipboard.

### File Operations

`cut` / `copy` / `delete` / `duplicate` resolve their targets with a unified
priority: **Visual selection > marked nodes > cursor node**. Root is always
excluded. When the operation runs from marked nodes, marks are cleared on
success (partial failures keep the marks for the failed/unattempted entries).

- **delete** — Delete target nodes. Routes through `confirm.delete` for the
  confirmation dialog, matching the buffer-edit delete path.
- **cut** — Move target node paths into the register with `cut` operation.
  `paste` later moves them.
- **copy** — Copy target node paths into the register with `copy` operation.
  `paste` later duplicates them.
- **paste** — Paste from the register into the directory under the cursor
  (or the parent of a file under the cursor; falls back to the explorer
  root). Appends `_copy` suffix on name collision and falls back to `_2`,
  `_3`... counters.
- **duplicate** — Duplicate each target node into its parent directory with
  the same `_copy` collision-resolution as `paste`. No prompt; works on
  files and directories.
- **quickfix** — Send target node paths to Neovim's quickfix list. Files
  only (directories are skipped with a warning). Preserves marks
  (non-destructive, unlike `cut`/`copy`/`delete`/`duplicate`). Opens the
  quickfix window automatically when `quickfix.auto_open` is `true`
  (default); when the explorer is a float, the float is closed first so
  it does not overlap the quickfix split. Replaces the current list; use
  `:colder` / `:cnewer` to navigate the quickfix history.
- **mark_toggle** — Mark/unmark target node(s). In Normal mode toggles the
  node under the cursor and moves the cursor down. In Visual mode toggles
  each node in the selection independently (no cursor advance).
- **mark_clear_all** — Clear all marks across the tree. No-op when no nodes
  are marked.

> **Note:** `mark_bulk_delete` and `mark_bulk_move` were removed in favour of
> the unified `delete` and the cut-paste flow. To move marked files to a new
> directory: `m` to mark, `gx` to cut, navigate to the target directory node,
> then `gp` to paste.

### Display

- **toggle_hidden** — Toggle visibility of hidden files (dotfiles).
- **toggle_gitignored** — Toggle visibility of git-ignored files.
- **toggle_git_changes** — Toggle a filter that shows only files with git
  changes (plus their ancestor directories). When turned on, ancestors of
  changed files are force-expanded so they are immediately visible; turning
  the filter off restores the original collapse state. While the filter is
  active, a `git changes` indicator is shown in the header (or float title)
  and the buffer shows `No git changes` when nothing matches. No-op with a
  warning when the current root is not a git repository.
- **next_git_change** — Jump to the next git-changed file in tree order,
  wrapping around at the end. Works across the entire tree: if the target
  file lives inside an unscanned or collapsed directory, the relevant
  ancestors are scanned and expanded automatically so the jump succeeds.
- **prev_git_change** — Jump to the previous git-changed file (reverse of
  `next_git_change`).
- **toggle_preview** — Toggle the file preview pane.
  *No default mapping.*
- **preview_scroll_down** — Scroll the preview window down by half a page.
  When preview is not visible, falls back to Neovim default `<C-f>`.
  Default mapping: `<C-f>`
- **preview_scroll_up** — Scroll the preview window up by half a page.
  When preview is not visible, falls back to Neovim default `<C-b>`.
  Default mapping: `<C-b>`
- **preview_scroll_page_down** — Scroll the preview window down by a full page.
  *No default mapping.*
- **preview_scroll_page_up** — Scroll the preview window up by a full page.
  *No default mapping.*

### Misc

- **refresh** — Rescan the filesystem and re-render the tree.
- **close** — Close the explorer window.
- **system_open** — Open the file with the system default application
  (`open` on macOS, `xdg-open` on Linux).
- **inspect** — Print the node data to the console (debug).
- **help** — Show keybinding help in a floating window.
- **split** — Open a new explorer split pane with the same root.
  Default mapping: `<C-w>v`
- **vsplit** — Open a new explorer in a horizontal split pane with the same root.
  Default mapping: `<C-w>s`
- **actions** — Open an action picker via `vim.ui.select` showing all
  registered actions with descriptions.

## API

### `eda.setup(opts)`

Initialize eda.nvim with the given configuration. Must be called before using
any features that depend on configuration (e.g., `hijack_netrw`,
`update_focused_file`).

### `eda.open(opts)`

Open the explorer. If an explorer is already visible, focuses it instead.

Parameters:
- `opts.dir` `string?` — Root directory path. Defaults to project root
  (detected via `root_markers`) or cwd.
- `opts.kind` `string?` — Window layout kind. Overrides `window.kind` config.

### `eda.toggle(opts)`

Toggle the explorer. Closes if visible, opens if not.

### `eda.close()`

Close the current explorer instance.

### `eda.navigate(path)`

Navigate to a specific file path in the tree. Scans ancestor directories as
needed and positions the cursor on the target node.

### `eda.get_current()`

Returns the current `eda.Explorer` instance, or `nil` if none is active.

### `eda.get_all()`

Returns a list of all active `eda.Explorer` instances.

### `eda.refresh_all()`

Rescan and re-render all active explorer instances.

### `eda.open_split(root_path)`

Open a new explorer in a vertical split with the given root path.

### `eda.open_vsplit(root_path)`

Open a new explorer in a horizontal split with the given root path.

### Action API

The action module is available at `require("eda.action")`.

#### `action.register(name, fn, opts?)`

Register a custom action.

Parameters:
- `name` `string` — Action name.
- `fn` `fun(ctx: eda.ActionContext)` — Action function.
- `opts` `table?` — Optional metadata.
  - `desc` `string?` — Human-readable description shown in the action picker.

```lua
local action = require("eda.action")
action.register("my_action", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if node then
    vim.notify("Selected: " .. node.path)
  end
end, { desc = "Show selected file path" })
```

#### `action.dispatch(name, ctx)`

Dispatch an action by name.

#### `action.list()`

Return a sorted list of all registered action names.

#### `action.get(name)`

Return the action function for the given name, or `nil`.

#### `action.get_entry(name)`

Return the full action entry for the given name, or `nil`. The entry is a
table with fields:
- `fn` — The action function.
- `desc` — The action description (may be `nil`).

### ActionContext

Every action receives an `eda.ActionContext` table:

- `store` — The tree node store (`eda.Store`).
- `buffer` — The explorer buffer (`eda.Buffer`).
- `window` — The explorer window (`eda.Window`).
- `scanner` — The filesystem scanner (`eda.Scanner`).
- `config` — The current configuration (`eda.Config`).
- `explorer` — The explorer instance (`eda.Explorer`).

## Events

eda.nvim fires `User` autocmds for integration with external plugins.

### `EdaTreeOpen`

Fired when the explorer window opens.

`data`: `{ root_path = string }`

### `EdaTreeClose`

Fired when the explorer window closes.

`data`: `{}`

### `EdaMutationPre`

Fired before file operations are executed.

`data`: `{ operations = table[] }`

### `EdaMutationPost`

Fired after file operations complete.

`data`: `{ operations = table[], results = table }`

Useful for integration with plugins like nvim-lsp-file-operations to
automatically update LSP workspace paths on file rename/move.

### `EdaRootChanged`

Fired when the explorer's root directory changes (via `parent`, `cwd`, or `cd`
actions).

`data`: `{ root_path = string, instance_id = integer }`

`instance_id` is the integer ID that identifies the Explorer instance (the same
value returned by `require("eda").get_all()` entries). eda.nvim allows multiple
explorer instances to coexist, so event listeners can use this field to filter
events to a specific instance when needed.

## Highlight Groups

All highlight groups can be customized via `on_highlight` or standard
`vim.api.nvim_set_hl()` calls.

### Structure

| Group              | Default Link  | Description               |
|--------------------|---------------|---------------------------|
| `EdaNormal`        | `Normal`      | Explorer window text      |
| `EdaNormalNC`      | `NormalNC`    | Unfocused explorer window |
| `EdaBorder`        | `FloatBorder` | Float window border       |
| `EdaTitle`         | `FloatTitle`  | Float window title        |
| `EdaCursorLine`    | `CursorLine`  | Cursor line highlight     |
| `EdaIndentMarker`  | `NonText`     | Tree indent guides        |
| `EdaRootName`      | `Directory`   | Root directory name       |
| `EdaDivider`       | `NonText`     | Header divider line       |
| `EdaFilterIndicator` | `Special`   | Active-filter indicator in header / float title |

### Filesystem

| Group                    | Default Link      | Description                  |
|--------------------------|-------------------|------------------------------|
| `EdaDirectoryName`       | `Directory`       | Directory name               |
| `EdaDirectoryIcon`       | `Directory`       | Directory icon               |
| `EdaOpenedDirectoryName` | `Directory`       | Expanded directory name      |
| `EdaEmptyDirectoryName`  | `Comment`         | Empty directory name         |
| `EdaFileName`            | `Normal`          | Regular file name            |
| `EdaSymlink`             | `Underlined`      | Symbolic link                |
| `EdaBrokenSymlink`       | `DiagnosticError` | Broken symbolic link         |
| `EdaSymlinkTarget`       | `Comment`         | Symlink target path suffix   |
| `EdaErrorNode`           | `DiagnosticError` | Node with errors             |
| `EdaLoadingNode`         | `Comment`         | Loading placeholder          |
| `EdaOpenedFile`          | `Special`         | File open in a buffer        |
| `EdaModifiedFile`        | `DiagnosticWarn`  | Modified file in a buffer    |

### Git Status

Each git status has three highlight groups: a base group (used for the suffix
icon by default), a `Name` group (applied to the file name), and an `Icon`
group (applied to the suffix icon). The `Icon` groups link to the base group
by default. The `Name` groups are transparent by default (file names keep their
original color), except for `EdaGitIgnoredName` which dims the file name.
Colorschemes or users can set `Name` groups to apply git status colors to file
names (e.g., `vim.api.nvim_set_hl(0, "EdaGitAddedName", { link = "EdaGitAdded" })`).
Directories only receive suffix highlighting (not name highlighting).

| Group                  | Default Link      | Description                |
|------------------------|-------------------|----------------------------|
| `EdaGitUntracked`      | `DiagnosticHint`  | Untracked (base)           |
| `EdaGitUntrackedName`  | _(none)_          | Untracked file name        |
| `EdaGitUntrackedIcon`  | `EdaGitUntracked` | Untracked suffix icon      |
| `EdaGitAdded`          | `DiagnosticOk`    | Added (base)               |
| `EdaGitAddedName`      | _(none)_          | Added file name            |
| `EdaGitAddedIcon`      | `EdaGitAdded`     | Added suffix icon          |
| `EdaGitModified`       | `DiagnosticWarn`  | Modified (base)            |
| `EdaGitModifiedName`   | _(none)_          | Modified file name         |
| `EdaGitModifiedIcon`   | `EdaGitModified`  | Modified suffix icon       |
| `EdaGitDeleted`        | `DiagnosticError` | Deleted (base)             |
| `EdaGitDeletedName`    | _(none)_          | Deleted file name          |
| `EdaGitDeletedIcon`    | `EdaGitDeleted`   | Deleted suffix icon        |
| `EdaGitRenamed`        | `DiagnosticWarn`  | Renamed (base)             |
| `EdaGitRenamedName`    | _(none)_          | Renamed file name          |
| `EdaGitRenamedIcon`    | `EdaGitRenamed`   | Renamed suffix icon        |
| `EdaGitStaged`         | `DiagnosticOk`    | Staged (base)              |
| `EdaGitStagedName`     | _(none)_          | Staged file name           |
| `EdaGitStagedIcon`     | `EdaGitStaged`    | Staged suffix icon         |
| `EdaGitConflict`       | `DiagnosticError` | Conflict (base)            |
| `EdaGitConflictName`   | _(none)_          | Conflict file name         |
| `EdaGitConflictIcon`   | `EdaGitConflict`  | Conflict suffix icon       |
| `EdaGitIgnored`        | `Comment`         | Ignored (base)             |
| `EdaGitIgnoredName`    | `EdaGitIgnored`   | Ignored file name          |
| `EdaGitIgnoredIcon`    | `EdaGitIgnored`   | Ignored suffix icon        |

### Operations

Marked nodes use a three-group pattern: `EdaMarked` (base), `EdaMarkedIcon`
(applied to the prefix icon), and `EdaMarkedName` (applied to the filename).
Both `Icon` and `Name` link to `EdaMarked` by default, so setting `EdaMarked`
alone styles icon and name together. To differentiate, override `EdaMarkedIcon`
or `EdaMarkedName` directly. The plugin strips `bg` / `ctermbg` from the
resolved `EdaMarked` on setup (and on `ColorScheme`) so marks do not clobber
`CursorLine` / `Visual`; direct overrides on `EdaMarkedIcon` / `EdaMarkedName`
keep their user-provided attributes untouched (same as git suffix icons).

| Group             | Default Link      | Description                    |
|-------------------|-------------------|--------------------------------|
| `EdaMarked`       | `Special`         | Marked node base. `bg` / `ctermbg` are stripped on setup (and re-stripped on `ColorScheme`) so marks do not clobber `CursorLine` / `Visual`. |
| `EdaMarkedIcon`   | `EdaMarked`       | Prefix icon on marked nodes. Override to style the icon only. |
| `EdaMarkedName`   | `EdaMarked`       | Filename portion on marked nodes. Override to style the name only, or set to `{}` to make it transparent (lets `EdaFileName` or any other overlay like `EdaCut` style the name instead). |
| `EdaCut`          | `italic = true`   | Cut node (italic, preserves git colors) |
| `EdaOpDeleteSign` | `DiagnosticError`  | Delete sign in confirm              |
| `EdaOpDeletePath` | `DiagnosticError`  | Delete path in confirm              |
| `EdaOpDeleteText` | `EdaOpDeleteSign`  | Delete count text in confirm title  |
| `EdaOpCreateSign` | `DiagnosticOk`     | Create sign in confirm              |
| `EdaOpCreatePath` | `DiagnosticOk`     | Create path in confirm              |
| `EdaOpCreateText` | `EdaOpCreateSign`  | Create count text in confirm title  |
| `EdaOpMoveSign`   | `DiagnosticWarn`   | Move sign in confirm                |
| `EdaOpMovePath`   | `DiagnosticWarn`   | Move path in confirm                |
| `EdaOpMoveText`   | `EdaOpMoveSign`    | Move count text in confirm title    |

### Confirmation Dialog

| Group              | Default Link  | Description                |
|--------------------|---------------|----------------------------|
| `EdaConfirmBorder` | `FloatBorder` | Confirmation dialog border |
| `EdaConfirmTitle`  | `FloatTitle`  | Confirmation dialog title  |
| `EdaConfirmFooter` | `Comment`     | Confirmation dialog footer |

### Help Dialog

| Group           | Default Link  | Description         |
|-----------------|---------------|---------------------|
| `EdaHelpBorder` | `FloatBorder` | Help dialog border  |
| `EdaHelpTitle`  | `FloatTitle`  | Help dialog title   |
| `EdaHelpFooter` | `Comment`     | Help dialog footer  |

### Full Name Popup

| Group                | Default Link    | Description                              |
|----------------------|-----------------|------------------------------------------|
| `EdaFullNameNormal`  | `EdaCursorLine` | Full filename floating window background |

## Healthcheck

Run `:checkhealth eda` to verify your setup. The healthcheck validates:

- Neovim version (>= 0.11 required)
- Git availability (optional, for git integration)
- Icon provider availability (configured provider only; no fallback)
- Number of registered actions
