local M = {}

---@alias eda.MappingValue string|fun(ctx?: eda.PublicContext)|false|eda.MappingDef

---@class eda.MappingDef
---@field action string|fun(ctx?: eda.PublicContext)
---@field desc? string

---@alias eda.ConfirmPathFormat "full"|"short"|"minimal"|fun(path: string, root_path: string): string

---@class eda.ConfirmSigns
---@field create string
---@field delete string
---@field move string

---@class eda.ConfirmConfig
---@field delete boolean
---@field move boolean|"overwrite_only"
---@field create boolean|integer
---@field path_format eda.ConfirmPathFormat
---@field signs eda.ConfirmSigns

---@class eda.UpdateFocusedFileConfig
---@field enable boolean
---@field update_root boolean

---@class eda.Config
---@field root_markers string[]
---@field show_hidden boolean
---@field show_gitignored boolean
---@field show_only_git_changes boolean
---@field ignore_patterns string[]|fun(root_path: string): string[]
---@field window eda.WindowConfig
---@field hijack_netrw boolean
---@field close_on_select boolean
---@field confirm boolean|eda.ConfirmConfig
---@field delete_to_trash boolean
---@field follow_symlinks boolean
---@field large_dir_threshold integer
---@field icon eda.IconConfig
---@field git eda.GitConfig
---@field indent eda.IndentConfig
---@field preview eda.PreviewConfig
---@field full_name eda.FullNameConfig
---@field mark eda.MarkConfig
---@field header eda.HeaderConfig|false
---@field expand_depth integer
---@field update_focused_file eda.UpdateFocusedFileConfig
---@field default_mappings? boolean
---@field mappings table<string, eda.MappingValue>
---@field on_highlight? fun(groups: table)
---@field select_window? fun(): integer?

---@alias eda.WindowDimension string|number|fun(): number

---@class eda.WindowConfig
---@field kind string
---@field border string
---@field kinds table<string, table>
---@field buf_opts table<string, any>
---@field win_opts table<string, any>

---@class eda.IconDirectoryConfig
---@field collapsed string
---@field expanded string
---@field empty string
---@field empty_open string

---@class eda.IconConfig
---@field separator string
---@field provider string
---@field directory eda.IconDirectoryConfig
---@field custom? fun(name: string, node: eda.TreeNode): (string?, string?)

---@class eda.GitConfig
---@field enabled boolean
---@field icons eda.GitIconsConfig

---@class eda.GitIconsConfig
---@field untracked string
---@field added string
---@field modified string
---@field deleted string
---@field renamed string
---@field staged string
---@field conflict string
---@field ignored string

---@class eda.IndentConfig
---@field width integer

---@class eda.PreviewConfig
---@field enabled boolean
---@field debounce integer
---@field max_file_size integer|fun(path: string): integer

---@class eda.FullNameConfig
---@field enabled boolean

---@class eda.MarkConfig
---@field icon string

---@alias eda.HeaderPosition "left" | "center" | "right"

---@class eda.HeaderConfig
---@field format string|fun(root_path: string): string|false
---@field position eda.HeaderPosition
---@field divider boolean

---@type eda.Config
local defaults = {
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
  },

  git = {
    enabled = true,
    icons = {
      untracked = "",
      added = "",
      modified = "",
      deleted = "",
      renamed = "",
      staged = "",
      conflict = "",
      ignored = "◌",
    },
  },

  indent = {
    width = 2,
  },

  preview = {
    enabled = false,
    debounce = 100,
    max_file_size = 1024 * 100,
  },

  full_name = {
    enabled = true,
  },

  mark = {
    -- U+F0132 (nf-md-checkbox_marked). Built via string.char to avoid PUA-character
    -- dropping by tooling that cannot safely pass private-use code points.
    icon = string.char(0xf3, 0xb0, 0x84, 0xb2),
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
}

---@type eda.Config
M._config = vim.deepcopy(defaults)

---Deep merge two tables. Override wins.
---@param base table
---@param override table
---@return table
local function deep_merge(base, override)
  local result = vim.deepcopy(base)
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

---@type eda.ConfirmConfig
local confirm_defaults = {
  delete = true,
  move = "overwrite_only",
  create = false,
  path_format = "short",
  signs = {
    create = "",
    delete = "",
    move = "",
  },
}

---Normalize confirm value to eda.ConfirmConfig.
---@param value boolean|table|nil
---@return eda.ConfirmConfig
function M._normalize_confirm(value)
  if value == true or value == nil then
    return vim.deepcopy(confirm_defaults)
  end
  if value == false then
    return {
      delete = false,
      move = false,
      create = false,
      path_format = "short",
      signs = vim.deepcopy(confirm_defaults.signs),
    }
  end
  if type(value) == "table" then
    local result = deep_merge(confirm_defaults, value)
    if result.create == 0 then
      result.create = false
    end
    return result
  end
  return vim.deepcopy(confirm_defaults)
end

---Setup configuration with user options.
---@param opts? table
function M.setup(opts)
  if opts then
    if opts.default_mappings == false then
      local base = vim.deepcopy(defaults)
      base.mappings = {}
      M._config = deep_merge(base, opts)
    else
      M._config = deep_merge(defaults, opts)
    end
  else
    M._config = vim.deepcopy(defaults)
  end
  M._config.confirm = M._normalize_confirm(M._config.confirm)
end

---Get the current configuration.
---@return eda.Config
function M.get()
  return M._config
end

return M
