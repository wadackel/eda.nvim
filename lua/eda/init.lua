local config = require("eda.config")
local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local Buffer = require("eda.buffer")
local Window = require("eda.window")
local action = require("eda.action")
local util = require("eda.util")
local decorator_mod = require("eda.render.decorator")
local git = require("eda.git")
local Watcher = require("eda.watcher")
local Preview = require("eda.preview")
local FullName = require("eda.full_name")

-- Load builtin actions (registers them on require)
require("eda.action.builtin")

local M = {}

local next_instance_id = 0

---@class eda.Explorer
---@field instance_id integer
---@field is_split boolean
---@field generation integer
---@field store eda.Store
---@field scanner eda.Scanner
---@field buffer eda.Buffer
---@field window eda.Window
---@field root_path string
---@field decorator_chain eda.DecoratorChain
---@field watcher eda.Watcher
---@field preview eda.Preview
---@field full_name eda.FullName
---@field _render_gen integer
---@field _last_painted_gen integer
---@field _incremental_hint? { toggled_node_id: integer }
---@field _render_preserving_edits fun(capture?: eda.EditCapture)?
---@field _refresh_for_navigation fun()?
---@field _empty_state_rendered? boolean
---@field _no_repo_notified? boolean

---@type eda.Explorer?
M._current = nil

---@type eda.Explorer[]
M._instances = {}

---@type table<string, { open_dirs: table<string, boolean>, cursor_path: string? }>
local state_cache = {}

-- Highlight groups with defaults
local highlight_groups = {
  EdaNormal = { link = "Normal" },
  EdaNormalNC = { link = "NormalNC" },
  EdaBorder = { link = "FloatBorder" },
  EdaTitle = { link = "FloatTitle" },
  EdaCursorLine = { link = "CursorLine" },
  EdaIndentMarker = { link = "NonText" },
  EdaDirectoryName = { link = "Directory" },
  EdaDirectoryIcon = { link = "Directory" },
  EdaOpenedDirectoryName = { link = "Directory" },
  EdaEmptyDirectoryName = { link = "Comment" },
  EdaFileName = { link = "Normal" },
  EdaSymlink = { link = "Underlined" },
  EdaBrokenSymlink = { link = "DiagnosticError" },
  EdaSymlinkTarget = { link = "Comment" },
  EdaErrorNode = { link = "DiagnosticError" },
  EdaLoadingNode = { link = "Comment" },
  EdaRootName = { link = "Directory" },
  EdaDivider = { link = "NonText" },
  EdaFilterIndicator = { link = "Special" },
  EdaOpenedFile = { link = "Special" },
  EdaModifiedFile = { link = "DiagnosticWarn" },
  EdaGitUntracked = { link = "DiagnosticHint" },
  EdaGitAdded = { link = "DiagnosticOk" },
  EdaGitModified = { link = "DiagnosticWarn" },
  EdaGitDeleted = { link = "DiagnosticError" },
  EdaGitRenamed = { link = "DiagnosticWarn" },
  EdaGitStaged = { link = "DiagnosticOk" },
  EdaGitConflict = { link = "DiagnosticError" },
  EdaGitIgnored = { link = "Comment" },
  EdaGitUntrackedName = {},
  EdaGitUntrackedIcon = { link = "EdaGitUntracked" },
  EdaGitAddedName = {},
  EdaGitAddedIcon = { link = "EdaGitAdded" },
  EdaGitModifiedName = {},
  EdaGitModifiedIcon = { link = "EdaGitModified" },
  EdaGitDeletedName = {},
  EdaGitDeletedIcon = { link = "EdaGitDeleted" },
  EdaGitRenamedName = {},
  EdaGitRenamedIcon = { link = "EdaGitRenamed" },
  EdaGitStagedName = {},
  EdaGitStagedIcon = { link = "EdaGitStaged" },
  EdaGitConflictName = {},
  EdaGitConflictIcon = { link = "EdaGitConflict" },
  EdaGitIgnoredName = { link = "EdaGitIgnored" },
  EdaGitIgnoredIcon = { link = "EdaGitIgnored" },
  EdaMarkedNode = { link = "Visual" },
  EdaCut = { italic = true },
  EdaOpDeleteSign = { link = "DiagnosticError" },
  EdaOpDeletePath = { link = "DiagnosticError" },
  EdaOpDeleteText = { link = "EdaOpDeleteSign" },
  EdaOpCreateSign = { link = "DiagnosticOk" },
  EdaOpCreatePath = { link = "DiagnosticOk" },
  EdaOpCreateText = { link = "EdaOpCreateSign" },
  EdaOpMoveSign = { link = "DiagnosticWarn" },
  EdaOpMovePath = { link = "DiagnosticWarn" },
  EdaOpMoveText = { link = "EdaOpMoveSign" },
  EdaConfirmBorder = { link = "FloatBorder" },
  EdaConfirmTitle = { link = "FloatTitle" },
  EdaConfirmFooter = { link = "Comment" },
  EdaHelpBorder = { link = "FloatBorder" },
  EdaHelpTitle = { link = "FloatTitle" },
  EdaHelpFooter = { link = "Comment" },
  EdaFullNameNormal = { link = "EdaCursorLine" },
}

local function setup_highlights()
  local cfg = config.get()
  if cfg.on_highlight then
    cfg.on_highlight(highlight_groups)
  end
  for name, spec in pairs(highlight_groups) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", { default = true }, spec))
  end
  -- Resolve git suffix/icon highlight groups to fg-only definitions.
  -- These groups are used as suffix virtual text with hl_mode="combine", which
  -- merges their attributes with line-level highlights (CursorLine). If the
  -- resolved highlight has a bg attribute (inherited from Diagnostic* links),
  -- it would override CursorLine's bg on suffix cells, creating a visual
  -- inconsistency. Stripping bg and keeping only fg preserves the intended
  -- colored suffix while letting CursorLine bg show through uniformly.
  -- Only link-based groups are resolved; directly-defined groups (via
  -- on_highlight) are left as-is to respect user customization.
  local git_suffix_icon_groups = {
    "EdaGitUntracked",
    "EdaGitAdded",
    "EdaGitModified",
    "EdaGitDeleted",
    "EdaGitRenamed",
    "EdaGitStaged",
    "EdaGitConflict",
    "EdaGitIgnored",
    "EdaGitUntrackedIcon",
    "EdaGitAddedIcon",
    "EdaGitModifiedIcon",
    "EdaGitDeletedIcon",
    "EdaGitRenamedIcon",
    "EdaGitStagedIcon",
    "EdaGitConflictIcon",
    "EdaGitIgnoredIcon",
    "EdaSymlinkTarget",
  }
  for _, name in ipairs(git_suffix_icon_groups) do
    local spec = highlight_groups[name]
    if spec and spec.link then
      local resolved = vim.api.nvim_get_hl(0, { name = name, link = false })
      if resolved and resolved.fg then
        vim.api.nvim_set_hl(0, name, { fg = resolved.fg })
      end
    end
  end
end

---Fire a User autocmd.
---@param pattern string
---@param data? table
local function fire_event(pattern, data)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern, data = data or {} })
end

-- Horizontal border characters per Neovim border style. Used to pad the float
-- title between the header and the filter indicator so the top border remains
-- continuous instead of showing a gap behind the padding spaces.
local BORDER_HORIZONTAL = {
  rounded = string.char(0xe2, 0x94, 0x80), -- ─
  single = string.char(0xe2, 0x94, 0x80), -- ─
  double = string.char(0xe2, 0x95, 0x90), -- ═
}

---Resolve the horizontal border character (and its highlight) for the current
---float border style, or nil when no faithful fill character exists (e.g.
---"solid", "none", "shadow"). Table-form borders read index 2 (the top edge).
---@param border string|table
---@return string?, string?
local function border_horizontal(border)
  if type(border) == "table" then
    local top = border[2]
    if type(top) == "string" and top ~= "" then
      return top, "EdaBorder"
    end
    if type(top) == "table" and type(top[1]) == "string" and top[1] ~= "" then
      return top[1], top[2] or "EdaBorder"
    end
    return nil, nil
  end
  if type(border) == "string" then
    local ch = BORDER_HORIZONTAL[border]
    if ch then
      return ch, "EdaBorder"
    end
  end
  return nil, nil
end

---Rebuild the float window title from current config + filter state.
---No-op on non-float windows. Called on `open`, on `cd`, after every render,
---and on `VimResized` so that `no_repo` auto-disable, filter toggles, and
---window resizes all reflect in the title.
---
---When both a header and the filter indicator are visible, the gap between
---them is filled with the border's horizontal character so the top edge stays
---continuous. Padding is width-dependent, so this must be re-called after
---resize.
---@param explorer eda.Explorer
local function refresh_float_title(explorer)
  local window = explorer.window
  if window.kind ~= "float" then
    return
  end
  local cfg = config.get()
  local filter_active = cfg.show_only_git_changes and true or false
  local header_cfg = cfg.header
  local header_format = nil
  if header_cfg and header_cfg ~= false and header_cfg.format and header_cfg.format ~= false then
    header_format = header_cfg.format
  end

  local chunks = nil
  local Painter = require("eda.render.painter")
  if header_format and header_cfg and header_cfg ~= false then
    local header_text = Painter._build_header_text(explorer.root_path, header_format)
    local header_str = " " .. header_text .. " "
    chunks = { { header_str, "EdaRootName" } }
    if filter_active then
      -- Right-edge padding only makes sense when the title is anchored to the
      -- left. `title_pos` (center/right) would shift the whole composite
      -- including the padding, so fall back to adjacent placement for those.
      local position = header_cfg.position or "left"
      if position == "left" then
        local win_width = nil
        if window.winid and vim.api.nvim_win_is_valid(window.winid) then
          win_width = vim.api.nvim_win_get_width(window.winid)
        end
        local header_w = vim.fn.strdisplaywidth(header_str)
        local filter_w = vim.fn.strdisplaywidth(Painter.FILTER_LABEL)
        local padding = win_width and (win_width - header_w - filter_w - 2) or 0
        local fill_char, fill_hl = border_horizontal(cfg.window.border)
        if padding > 0 and fill_char then
          chunks[#chunks + 1] = { string.rep(fill_char, padding), fill_hl }
        end
      end
      chunks[#chunks + 1] = { Painter.FILTER_LABEL, "EdaFilterIndicator" }
    end
  elseif filter_active then
    chunks = { { Painter.FILTER_LABEL, "EdaFilterIndicator" } }
  end

  window:set_header_text(chunks)
end

---@param explorer eda.Explorer
local function make_ctx(explorer)
  return {
    store = explorer.store,
    buffer = explorer.buffer,
    window = explorer.window,
    scanner = explorer.scanner,
    config = config.get(),
    explorer = explorer,
  }
end

---@class eda.PublicContext
---@field get_node fun(): eda.TreeNode?
---@field get_root fun(): eda.TreeNode?
---@field get_cwd fun(): string
---@field get_config fun(): eda.Config
---@field refresh fun()

---@param explorer eda.Explorer
---@return eda.PublicContext
local function make_public_ctx(explorer)
  local ctx = make_ctx(explorer)
  return {
    get_node = function()
      return ctx.buffer:get_cursor_node(ctx.window.winid)
    end,
    get_root = function()
      return ctx.store:get(ctx.store.root_id)
    end,
    get_cwd = function()
      return explorer.root_path
    end,
    get_config = function()
      return ctx.config
    end,
    refresh = function()
      ctx.buffer:render(ctx.store)
    end,
  }
end

-- Resolve root directory
---@param opts? table
---@return string
local function resolve_root(opts)
  opts = opts or {}
  if opts.dir then
    local resolved = vim.fn.fnamemodify(opts.dir, ":p"):gsub("/$", "")
    -- Preserve filesystem root "/" (gsub would strip it to "")
    if resolved == "" then
      resolved = "/"
    end
    return resolved
  end

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path ~= "" and vim.fn.filereadable(buf_path) == 1 then
    local buf_dir = vim.fn.fnamemodify(buf_path, ":h")
    local cfg = config.get()

    -- Try to find project root using root_markers
    for _, marker in ipairs(cfg.root_markers) do
      local root = vim.fs.root(buf_dir, marker)
      if root and vim.startswith(buf_path, root .. "/") then
        return root
      end
    end

    -- No matching root marker found or file is outside all roots;
    -- fall back to the file's parent directory
    return buf_dir
  end

  return vim.fn.getcwd()
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  setup_highlights()

  local cfg = config.get()

  -- Hijack netrw
  if cfg.hijack_netrw then
    vim.g.loaded_netrwPlugin = 1
    vim.g.loaded_netrw = 1
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("eda_netrw_hijack", { clear = true }),
      callback = function(args)
        local path = vim.api.nvim_buf_get_name(args.buf)
        if vim.fn.isdirectory(path) == 1 then
          vim.schedule(function()
            local dir_buf = args.buf
            M.open({ dir = path, kind = "replace" })
            if vim.api.nvim_buf_is_valid(dir_buf) and dir_buf ~= vim.api.nvim_get_current_buf() then
              vim.api.nvim_buf_delete(dir_buf, { force = true })
            end
          end)
        end
      end,
    })
  end

  -- Update focused file
  if cfg.update_focused_file and cfg.update_focused_file.enable then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("eda_update_focused", { clear = true }),
      callback = function(args)
        if vim.bo[args.buf].filetype == "eda" or vim.bo[args.buf].filetype == "eda_confirm" then
          return
        end
        local path = vim.api.nvim_buf_get_name(args.buf)
        if path ~= "" and vim.fn.filereadable(path) == 1 and M._current then
          M.navigate(path)
        end
      end,
    })
  end

  -- Detect Neovim standard splits on eda buffers
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("eda_split_detect", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype ~= "eda" then
        return
      end
      -- Check if this buffer already belongs to an existing explorer
      for _, inst in ipairs(M._instances) do
        if inst.buffer.bufnr == args.buf then
          if not inst.window.winid then
            return
          end
          local current_win = vim.api.nvim_get_current_win()
          if current_win ~= inst.window.winid then
            vim.schedule(function()
              if vim.api.nvim_win_is_valid(current_win) then
                vim.api.nvim_win_close(current_win, true)
                vim.notify("eda: split is not supported on eda buffer", vim.log.levels.WARN)
              end
            end)
          end
          return
        end
      end
      -- New window with an eda buffer that has no explorer; extract root from buffer name
      local buf_name = vim.api.nvim_buf_get_name(args.buf)
      local root = buf_name:match("^eda://([^#]+)")
      if root then
        vim.schedule(function()
          M.open({ dir = root, kind = "replace", _new_instance = true })
        end)
      end
    end,
  })
end

---@param opts? table
function M.open(opts)
  opts = opts or {}

  if M._current and not opts._new_instance then
    if M._current.window:is_visible() then
      M._current.window:focus()
      return
    end
    -- Window was closed externally; clean up stale state
    M.close()
  end

  local cfg = config.get()
  local root_path = resolve_root(opts)
  local kind = opts.kind or cfg.window.kind

  local instance_id = next_instance_id
  next_instance_id = next_instance_id + 1
  local is_split = (opts._new_instance == true)

  local store = Store.new()
  store:set_root(root_path)

  local scanner = Scanner.new(store, cfg)
  local buffer = Buffer.new(root_path, cfg, is_split and instance_id or nil)
  local window = Window.new(kind, cfg)
  local watcher = Watcher.new()
  local preview = Preview.new(cfg.preview)
  local full_name = FullName.new(cfg.full_name)

  -- Setup decorator chain
  local chain = decorator_mod.Chain.new()
  chain:add(decorator_mod.icon_decorator)
  chain:add(decorator_mod.symlink_decorator)
  if cfg.git.enabled then
    chain:add(decorator_mod.dotgit_decorator)
    chain:add(decorator_mod.git_decorator)
  end
  chain:add(decorator_mod.cut_decorator)

  ---@type eda.Explorer
  local explorer = {
    instance_id = instance_id,
    is_split = is_split,
    generation = 0,
    store = store,
    scanner = scanner,
    buffer = buffer,
    window = window,
    root_path = root_path,
    decorator_chain = chain,
    watcher = watcher,
    preview = preview,
    full_name = full_name,
    _render_gen = 0,
    _last_painted_gen = -1,
  }

  M._current = explorer
  table.insert(M._instances, explorer)

  -- Track current explorer on buffer focus
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = buffer.bufnr,
    callback = function()
      M._current = explorer
    end,
  })

  -- Helper: render with decorators (reads from explorer.* fields)
  local function render_with_decorators()
    local buf = explorer.buffer
    local win = explorer.window
    local st = explorer.store
    local rp = explorer.root_path
    local ch = explorer.decorator_chain
    local cfg_now = config.get()
    local k = win.kind

    -- Suppress async repaint while user has unsaved edits
    if vim.bo[buf.bufnr].modified then
      return
    end
    -- Skip render if nothing has changed since last paint
    if explorer._render_gen == explorer._last_painted_gen then
      return
    end
    if not buf.target_node_id then
      buf:save_cursor(win.winid)
    end
    local git_status = git.get_cached(rp)

    -- If the filter was preset via setup() on a non-git directory, there is no
    -- way to report changes. Auto-disable the filter once per explorer so that
    -- subsequent renders fall through to the normal tree instead of silently
    -- filtering everything out.
    if cfg_now.show_only_git_changes and git.get_status_ready(rp) == "no_repo" then
      cfg_now.show_only_git_changes = false
      if not explorer._no_repo_notified then
        vim.notify("eda: not a git repository, git changes filter disabled", vim.log.levels.WARN)
        explorer._no_repo_notified = true
      end
    end

    -- Empty-state branch: "Git status loading..." when filter is on but status not yet ready
    -- (either still loading after git.status() was invoked, or not yet invoked = nil).
    -- Excludes "ready" and "no_repo" states.
    if cfg_now.show_only_git_changes then
      local ready = git.get_status_ready(rp)
      if ready == "loading" or ready == nil then
        vim.api.nvim_buf_set_lines(buf.bufnr, 0, -1, false, { "Git status loading..." })
        -- nvim_buf_set_lines marks the buffer modified; clear it so the next render
        -- (after git status becomes ready) is not skipped by the modified-guard.
        vim.bo[buf.bufnr].modified = false
        buf.flat_lines = {}
        explorer._last_painted_gen = explorer._render_gen
        explorer._incremental_hint = nil
        explorer._empty_state_rendered = true
        buf.target_node_id = nil
        -- Sync float title on this early-return path so toggling `gs` during
        -- loading still updates the indicator instead of waiting for the next
        -- full render.
        if k == "float" then
          refresh_float_title(explorer)
        end
        return
      end
    end

    -- Build filters and should_descend for show_gitignored and show_only_git_changes.
    -- show_only_git_changes requires ready git status; "changed_set" = reported files +
    -- all their ancestor dir paths (computed on each render; typical 10-100 entries).
    local filters = {}
    local should_descend = nil
    if not cfg_now.show_gitignored and git_status then
      local is_gitignored = require("eda.git").is_gitignored
      table.insert(filters, function(node)
        if node.name == ".git" and node.type == "directory" then
          return false
        end
        if node.path:find("/.git/", 1, true) then
          return false
        end
        if git_status[node.path] == "!" then
          return false
        end
        return not is_gitignored(git_status, node.path)
      end)
    end
    if cfg_now.show_only_git_changes then
      local reported = git.get_reported_changes(rp)
      if reported then
        local changed_set = {}
        for path in pairs(reported) do
          changed_set[path] = true
          local dir = path:match("^(.*)/[^/]*$")
          while dir and #dir > #rp do
            changed_set[dir] = true
            dir = dir:match("^(.*)/[^/]*$")
          end
        end
        table.insert(filters, function(node)
          return changed_set[node.path] == true
        end)
        should_descend = function(node)
          return node.open or changed_set[node.path] == true
        end
      end
    end
    local flatten_opts = nil
    if #filters > 0 or should_descend then
      flatten_opts = {
        filter = (#filters == 1) and filters[1] or (#filters > 1 and function(node)
          for _, f in ipairs(filters) do
            if not f(node) then
              return false
            end
          end
          return true
        end or nil),
        should_descend = should_descend,
      }
    end
    local flat_lines = require("eda.render.flatten").flatten(st, st.root_id, flatten_opts)
    local ctx = { store = st, git_status = git_status, config = cfg_now }
    local decorations = ch:decorate(flat_lines, ctx)
    buf.flat_lines = flat_lines
    local paint_opts = {
      root_path = rp,
      header = cfg_now.header,
      kind = k,
      icon = cfg_now.icon,
      filter_active = cfg_now.show_only_git_changes and true or false,
    }
    if cfg_now.show_only_git_changes and #flat_lines == 0 and git.get_status_ready(rp) == "ready" then
      local Painter = require("eda.render.painter")
      paint_opts.empty_message = Painter.FILTER_ICON .. "  No git changes"
    end
    -- Try incremental paint for single-directory toggle operations
    local used_incremental = false
    if #buf.painter._flat_lines > 0 and explorer._incremental_hint then
      ---@type { toggled_node_id: integer }
      local hint = explorer._incremental_hint
      explorer._incremental_hint = nil
      used_incremental = buf.painter:paint_incremental(flat_lines, decorations, paint_opts, hint)
    end
    if not used_incremental then
      buf.painter:paint(flat_lines, decorations, paint_opts)
    end
    buf:restore_cursor()
    buf.target_node_id = nil
    explorer._last_painted_gen = explorer._render_gen
    if k == "float" then
      refresh_float_title(explorer)
    end
  end

  local render_scheduled = false
  local function schedule_render()
    if render_scheduled then
      return
    end
    render_scheduled = true
    local gen = explorer.generation
    vim.schedule(function()
      render_scheduled = false
      if explorer.generation ~= gen then
        return
      end
      render_with_decorators()
    end)
  end

  -- Mark render as needed (call before render/schedule_render when state changes)
  local function mark_render_dirty()
    explorer._render_gen = explorer._render_gen + 1
  end

  -- Override buffer:render to use decorators
  buffer.render = function(_self_buf, _s)
    mark_render_dirty()
    render_with_decorators()
  end

  -- Edit-preserving render: capture edits → full repaint → replay edits
  local edit_preserve = require("eda.buffer.edit_preserve")
  local function render_preserving_edits(existing_capture)
    -- Clear incremental hint: dirty-buffer renders must always do a full paint
    explorer._incremental_hint = nil

    local buf = explorer.buffer
    local st = explorer.store
    local cfg_now = config.get()

    local capture = existing_capture
      or edit_preserve.capture(buf.bufnr, buf.painter, st, explorer.root_path, cfg_now.indent.width)

    -- Temporarily clear modified to bypass render_with_decorators guard
    vim.bo[buf.bufnr].modified = false
    mark_render_dirty()
    render_with_decorators()

    if edit_preserve.has_edits(capture) then
      edit_preserve.replay(buf.bufnr, buf.painter, capture, st)
      buf.flat_lines = buf.painter._flat_lines
    end
  end
  explorer._render_preserving_edits = render_preserving_edits

  -- Navigation-safe refresh: honors buffer.target_node_id even when the buffer
  -- is dirty. Without this, render_with_decorators early-returns on modified=true
  -- and the cursor does not move to the target node.
  local function refresh_for_navigation()
    if vim.bo[buffer.bufnr].modified then
      render_preserving_edits(nil)
    else
      mark_render_dirty()
      render_with_decorators()
    end
  end
  explorer._refresh_for_navigation = refresh_for_navigation

  -- Setup keymaps via action dispatch
  buffer:set_mappings(cfg.mappings, function(action_name)
    action.dispatch(action_name, make_ctx(explorer))
  end, function()
    return make_public_ctx(explorer)
  end)

  -- Setup BufWriteCmd for buffer editing
  buffer:set_write_handler(function()
    M._handle_write(explorer)
  end)

  -- Setup CursorMoved for preview and full-name popup
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buffer.bufnr,
    callback = function()
      local node = buffer:get_cursor_node(window.winid)
      preview:update(node)
      full_name:update(window.winid, buffer.painter, buffer.flat_lines)
    end,
  })

  -- Close full-name popup when leaving the eda buffer
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buffer.bufnr,
    callback = function()
      full_name:close()
    end,
  })

  -- Capture current buffer path before opening the eda window
  local current_buf_path = vim.api.nvim_buf_get_name(0)

  -- Set float window title from header config
  if kind == "float" and cfg.header and cfg.header ~= false then
    window:set_header_position(cfg.header.position)
  end
  if kind == "float" then
    refresh_float_title(explorer)
  end

  -- Open window
  window:open(buffer.bufnr)
  preview:attach(window)

  -- Register WinClosed handler for float windows
  if kind == "float" then
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(window.winid),
      once = true,
      callback = function()
        if M._current == explorer then
          M.close()
        end
      end,
    })
  end

  -- Setup VimResized for repositioning float windows
  local resize_augroup = vim.api.nvim_create_augroup("eda_resize_" .. buffer.bufnr, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_augroup,
    callback = function()
      window:reposition()
      -- Recompute right-aligned padding in the float title for the new width.
      refresh_float_title(explorer)
      require("eda.buffer.help").reposition()
      require("eda.buffer.confirm").reposition()
      preview:reposition()
      full_name:close()
    end,
  })

  fire_event("EdaTreeOpen", { root_path = root_path })

  -- Determine target path for cursor positioning
  local target_path = nil
  if current_buf_path ~= "" and vim.startswith(current_buf_path, root_path .. "/") then
    target_path = current_buf_path
  end

  -- Path to expand (used by parent action to preserve old root's open state)
  local expand_path = opts._expand_path

  -- Scan, fetch git status, and render
  local function on_initial_scan_complete()
    vim.schedule(function()
      if not util.is_valid_buf(buffer.bufnr) then
        return
      end

      -- Position cursor on target file if applicable
      if target_path then
        local node = store:get_by_path(target_path)
        if node then
          buffer.target_node_id = node.id
        else
          -- Fallback: resolve real path through symlink nodes
          local resolved = store:resolve_symlink_path(target_path)
          if resolved then
            scanner:scan_ancestors(resolved, function()
              vim.schedule(function()
                if not util.is_valid_buf(buffer.bufnr) then
                  return
                end
                local resolved_node = store:get_by_path(resolved)
                if resolved_node then
                  buffer.target_node_id = resolved_node.id
                end
                mark_render_dirty()
                schedule_render()
              end)
            end)
          end
        end
      end

      mark_render_dirty()
      render_with_decorators()

      -- Restore cached state (directory open/close and cursor position)
      local cached = state_cache[root_path]
      if cached then
        -- Phase 1: Apply cached open states to all current nodes
        for _, node in pairs(store.nodes) do
          if node.type == "directory" and cached.open_dirs[node.path] then
            node.open = true
          end
        end

        -- Phase 2: Iteratively scan open+unloaded directories
        scanner:scan_open_unloaded(cached.open_dirs, function()
          vim.schedule(function()
            if not util.is_valid_buf(buffer.bufnr) then
              return
            end
            -- Restore cursor position from cache if no target_path
            if not target_path and cached.cursor_path then
              local cursor_node = store:get_by_path(cached.cursor_path)
              if cursor_node then
                buffer.target_node_id = cursor_node.id
              end
            end
            mark_render_dirty()
            schedule_render()
          end)
        end)
      end

      -- Expand path from parent action (scan ancestors and open directories along the path)
      if expand_path then
        scanner:scan_ancestors(expand_path, function()
          vim.schedule(function()
            if not util.is_valid_buf(buffer.bufnr) then
              return
            end
            local ep_node = store:get_by_path(expand_path)
            if ep_node then
              -- Walk up from expand_path to root, opening each directory
              ---@type eda.TreeNode?
              local current = ep_node
              while current do
                if current.type == "directory" then
                  current.open = true
                end
                if current.parent_id then
                  current = store:get(current.parent_id)
                else
                  break
                end
              end
              buffer.target_node_id = ep_node.id
            end
            mark_render_dirty()
            schedule_render()
          end)
        end)
      end

      -- Fetch git status after initial render
      if cfg.git.enabled then
        git.status(root_path, function(_status)
          if not util.is_valid_buf(buffer.bufnr) then
            return
          end
          -- Always re-render after git.status resolves (ready/no_repo/error) so
          -- state-dependent branches like show_only_git_changes auto-disable fire.
          mark_render_dirty()
          schedule_render()
        end)
      end

      -- Setup watcher on root directory
      watcher:watch(root_path, function()
        if not util.is_valid_buf(buffer.bufnr) then
          watcher:unwatch_all()
          return
        end
        scanner:rescan_preserving_state(store.root_id, function()
          vim.schedule(function()
            if not util.is_valid_buf(buffer.bufnr) then
              return
            end
            mark_render_dirty()
            schedule_render()
          end)
        end)
      end)
    end)
  end

  if target_path then
    scanner:scan_ancestors(target_path, on_initial_scan_complete)
  else
    scanner:scan(store.root_id, on_initial_scan_complete)
  end
end

---Determine whether operations need user confirmation based on confirm config.
---@param conf boolean|eda.ConfirmConfig
---@param operations table[]
---@return boolean
function M._should_confirm(conf, operations)
  local create_count = 0
  for _, op in ipairs(operations) do
    if op.type == "delete" then
      if conf.delete == true then
        return true
      end
    elseif op.type == "move" and op.dst then
      if conf.move == true then
        return true
      elseif conf.move == "overwrite_only" then
        if vim.uv.fs_stat(op.dst) then
          return true
        end
      end
    elseif op.type == "create" then
      if conf.create == true then
        return true
      elseif type(conf.create) == "number" then
        create_count = create_count + 1
      end
    end
  end
  if type(conf.create) == "number" and create_count > conf.create then
    return true
  end
  return false
end

---Handle :w in the eda buffer.
---@param explorer eda.Explorer
function M._handle_write(explorer)
  local Parser = require("eda.buffer.parser")
  local Diff = require("eda.tree.diff")
  local Fs = require("eda.fs")
  local Confirm = require("eda.buffer.confirm")

  local buffer = explorer.buffer
  local store = explorer.store
  local cfg = config.get()
  local ns_id = buffer.painter.ns_ids

  -- Parse buffer lines (skip header lines)
  local parsed =
    Parser.parse_lines(buffer.bufnr, ns_id, cfg.indent.width, explorer.root_path, buffer.painter.header_lines)

  -- Compute diff against snapshot
  local snapshot = buffer.painter:get_snapshot()
  local operations = Diff.compute(parsed, snapshot, store)

  if #operations == 0 then
    vim.bo[buffer.bufnr].modified = false
    buffer:render(store)
    return
  end

  -- Validate
  local validation = Diff.validate(operations, store)
  if not validation.valid then
    vim.notify("Validation errors:\n" .. table.concat(validation.errors, "\n"), vim.log.levels.ERROR)
    return
  end

  -- Check if confirmation is needed
  local needs_confirm = M._should_confirm(cfg.confirm, operations)

  local function execute()
    fire_event("EdaMutationPre", { operations = operations })
    Fs.execute_operations(operations, { delete_to_trash = cfg.delete_to_trash }, function(result)
      vim.schedule(function()
        if not util.is_valid_buf(buffer.bufnr) then
          return
        end
        fire_event("EdaMutationPost", { operations = operations, results = result })
        if result.error and #result.completed == 0 then
          -- No operations succeeded; keep buffer dirty
          return
        end
        -- Re-scan and re-render (even on partial failure, reflect successful operations)
        explorer.scanner:rescan_preserving_state(store.root_id, function()
          vim.schedule(function()
            if not util.is_valid_buf(buffer.bufnr) then
              return
            end
            if result.error then
              -- Partial failure: rescan completed but keep buffer dirty, report error
              buffer:render(store)
              vim.notify(
                "Applied " .. #result.completed .. " operation(s), error: " .. result.error,
                vim.log.levels.WARN
              )
            else
              vim.bo[buffer.bufnr].modified = false
              buffer:render(store)
              vim.notify("Applied " .. #result.completed .. " operation(s)")
            end
          end)
        end)
      end)
    end)
  end

  if needs_confirm then
    vim.schedule(function()
      Confirm.show(operations, explorer.root_path, execute, function()
        -- Cancel: do nothing, buffer stays dirty
      end)
    end)
  else
    execute()
  end
end

---Change the root directory of an existing explorer instance.
---@param explorer eda.Explorer
---@param new_path string
---@param opts? { _expand_path?: string }
function M._change_root(explorer, new_path, opts)
  opts = opts or {}

  -- Block if buffer has unsaved edits
  if vim.bo[explorer.buffer.bufnr].modified then
    vim.notify("eda: save or discard changes before changing root", vim.log.levels.WARN)
    return
  end

  -- Increment generation to invalidate stale callbacks
  explorer.generation = explorer.generation + 1

  -- Unwatch old root
  explorer.watcher:unwatch_all()

  -- Reinitialize store, scanner
  local cfg = config.get()
  local new_store = Store.new()
  new_store:set_root(new_path)
  local new_scanner = Scanner.new(new_store, cfg)

  explorer.store = new_store
  explorer.scanner = new_scanner
  explorer.root_path = new_path

  -- Update buffer name for uniqueness
  local buf_name = "eda://" .. new_path
  if explorer.is_split then
    buf_name = buf_name .. "#" .. explorer.instance_id
  end
  vim.api.nvim_buf_set_name(explorer.buffer.bufnr, buf_name)

  -- Update float window title if applicable
  if explorer.window.kind == "float" then
    refresh_float_title(explorer)
  end

  -- Expand path support (used by parent action)
  local expand_path = opts._expand_path
  local gen = explorer.generation

  local function on_scan_complete()
    vim.schedule(function()
      if explorer.generation ~= gen then
        return
      end
      if not util.is_valid_buf(explorer.buffer.bufnr) then
        return
      end

      explorer.buffer:render(explorer.store)

      -- Expand path from parent action
      if expand_path then
        explorer.scanner:scan_ancestors(expand_path, function()
          vim.schedule(function()
            if explorer.generation ~= gen then
              return
            end
            if not util.is_valid_buf(explorer.buffer.bufnr) then
              return
            end
            local ep_node = explorer.store:get_by_path(expand_path)
            if ep_node then
              ---@type eda.TreeNode?
              local current_node = ep_node
              while current_node do
                if current_node.type == "directory" then
                  current_node.open = true
                end
                if current_node.parent_id then
                  current_node = explorer.store:get(current_node.parent_id)
                else
                  break
                end
              end
              explorer.buffer.target_node_id = ep_node.id
            end
            explorer.buffer:render(explorer.store)
          end)
        end)
      end

      -- Fetch git status
      if cfg.git.enabled then
        git.status(new_path, function(_status)
          if explorer.generation ~= gen then
            return
          end
          if not util.is_valid_buf(explorer.buffer.bufnr) then
            return
          end
          explorer.buffer:render(explorer.store)
        end)
      end

      -- Setup watcher on new root
      explorer.watcher:watch(new_path, function()
        if explorer.generation ~= gen then
          return
        end
        if not util.is_valid_buf(explorer.buffer.bufnr) then
          explorer.watcher:unwatch_all()
          return
        end
        explorer.scanner:rescan_preserving_state(explorer.store.root_id, function()
          vim.schedule(function()
            if explorer.generation ~= gen then
              return
            end
            if not util.is_valid_buf(explorer.buffer.bufnr) then
              return
            end
            explorer.buffer:render(explorer.store)
          end)
        end)
      end)
    end)
  end

  explorer.scanner:scan(new_store.root_id, on_scan_complete)

  fire_event("EdaRootChanged", { root_path = new_path, instance_id = explorer.instance_id })
end

---@param opts? table
function M.toggle(opts)
  if M._current and M._current.window:is_visible() then
    M.close()
  else
    M.open(opts)
  end
end

function M.close()
  local current = M._current
  if not current then
    return
  end

  -- Save state for this root before cleanup (only for non-split instances)
  if not current.is_split then
    local open_dirs = {}
    for _, node in pairs(current.store.nodes) do
      if node.type == "directory" and node.open and node.id ~= current.store.root_id then
        open_dirs[node.path] = true
      end
    end
    local cursor_path = nil
    if util.is_valid_win(current.window.winid) then
      local cursor_node = current.buffer:get_cursor_node(current.window.winid)
      if cursor_node then
        cursor_path = cursor_node.path
      end
    end
    state_cache[current.root_path] = {
      open_dirs = open_dirs,
      cursor_path = cursor_path,
    }
  end

  -- Remove from instances list
  for i, inst in ipairs(M._instances) do
    if inst == current then
      table.remove(M._instances, i)
      break
    end
  end
  -- Set _current to next available instance or nil
  M._current = M._instances[#M._instances]

  current.preview:close()
  current.full_name:destroy()
  pcall(vim.api.nvim_del_augroup_by_name, "eda_preview_" .. current.buffer.bufnr)
  current.watcher:unwatch_all()
  current.buffer:destroy()
  current.window:close()
  fire_event("EdaTreeClose")
end

---Navigate to a specific path in the tree.
---@param path string
function M.navigate(path)
  if not M._current then
    return
  end
  ---@type eda.Explorer
  local explorer = M._current
  explorer.scanner:scan_ancestors(path, function()
    vim.schedule(function()
      if not util.is_valid_buf(explorer.buffer.bufnr) then
        return
      end
      local node = explorer.store:get_by_path(path)
      if node then
        explorer.buffer.target_node_id = node.id
      end
      if explorer._refresh_for_navigation then
        explorer._refresh_for_navigation()
      else
        explorer.buffer:render(explorer.store)
      end
    end)
  end)
end

---Get the current explorer instance.
---@return eda.Explorer?
function M.get_current()
  return M._current
end

---Get all active explorer instances.
---@return eda.Explorer[]
function M.get_all()
  return M._instances
end

---Refresh all active explorer instances.
function M.refresh_all()
  for _, explorer in ipairs(M._instances) do
    if util.is_valid_buf(explorer.buffer.bufnr) then
      explorer.scanner:rescan_preserving_state(explorer.store.root_id, function()
        vim.schedule(function()
          if util.is_valid_buf(explorer.buffer.bufnr) then
            explorer.buffer:render(explorer.store)
          end
        end)
      end)
    end
  end
end

---Open a new explorer in a vertical split.
---@param root_path string
function M.open_split(root_path)
  -- Move to target window and create a vsplit
  if M._current then
    local target_win = M._current.window:get_target_winid()
    if target_win then
      vim.api.nvim_set_current_win(target_win)
    end
  end
  vim.cmd("vsplit")
  -- Open a new explorer in the new window
  M.open({ dir = root_path, kind = "replace", _new_instance = true })
end

---Open a new explorer in a horizontal split.
---@param root_path string
function M.open_vsplit(root_path)
  if M._current then
    local target_win = M._current.window:get_target_winid()
    if target_win then
      vim.api.nvim_set_current_win(target_win)
    end
  end
  vim.cmd("split")
  M.open({ dir = root_path, kind = "replace", _new_instance = true })
end

return M
