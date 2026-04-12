local Node = require("eda.tree.node")
local action = require("eda.action")
local git = require("eda.git")
local Flatten = require("eda.render.flatten")

local M = {}

---Find the next or previous entry in a sorted changed_indexes list relative to
---cursor_index, wrapping around at the ends.
---@param changed_indexes integer[]  ascending sorted line indexes of changed files
---@param cursor_index integer?  current cursor line index (nil if cursor not on a changed line)
---@param dir "next"|"prev"
---@return integer?  target line index, or nil if changed_indexes is empty
local function find_next_change_index(changed_indexes, cursor_index, dir)
  local n = #changed_indexes
  if n == 0 then
    return nil
  end

  if cursor_index == nil then
    return dir == "next" and changed_indexes[1] or changed_indexes[n]
  end

  if dir == "next" then
    for _, idx in ipairs(changed_indexes) do
      if idx > cursor_index then
        return idx
      end
    end
    return changed_indexes[1] -- wrap
  else
    for i = n, 1, -1 do
      if changed_indexes[i] < cursor_index then
        return changed_indexes[i]
      end
    end
    return changed_indexes[n] -- wrap
  end
end

M._find_next_change_index = find_next_change_index

---Helper: get the main eda module (lazy require to avoid circular deps).
---@return table
local function get_eda()
  ---@diagnostic disable-next-line: redundant-return-value
  return require("eda")
end

---Helper: refresh the explorer display.
---@param ctx eda.ActionContext
local function refresh(ctx)
  ctx.buffer:render(ctx.store)
end

---Helper: refresh preserving user edits when buffer is dirty.
---@param ctx eda.ActionContext
---@param capture eda.EditCapture? Pre-computed capture to reuse (avoids redundant capture() call)
local function refresh_preserving(ctx, capture)
  if vim.bo[ctx.buffer.bufnr].modified then
    ctx.explorer._render_preserving_edits(capture)
  else
    refresh(ctx)
  end
end

---Check if collapsing dir_path would lose user edits inside it.
---@param capture eda.EditCapture
---@param dir_path string
---@return boolean
local function has_edits_under(capture, dir_path)
  local prefix = dir_path .. "/"
  for _, op in ipairs(capture.operations) do
    if (op.path and op.path:sub(1, #prefix) == prefix) or (op.src and op.src:sub(1, #prefix) == prefix) then
      return true
    end
  end
  return false
end

---Navigate to parent directory at root boundary.
---@param ctx eda.ActionContext
---@return boolean success false if already at filesystem root
local function navigate_to_parent_root(ctx)
  local root = ctx.explorer.root_path
  if root == "/" then
    return false -- filesystem root
  end
  local parent_path = vim.fn.fnamemodify(root, ":h")
  if parent_path == root then
    return false -- filesystem root
  end
  local old_root = ctx.explorer.root_path
  get_eda()._change_root(ctx.explorer, parent_path, { _expand_path = old_root })
  return true
end

---Returns true when eda should close after file selection.
---Float windows always close; other kinds respect close_on_select config.
---@param ctx eda.ActionContext
---@return boolean
local function should_close_on_select(ctx)
  return ctx.window.kind == "float" or ctx.config.close_on_select
end

-- select: open file or toggle directory
action.register("select", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  if Node.is_dir(node) then
    node.open = not node.open
    ctx.explorer._incremental_hint = { toggled_node_id = node.id }
    if node.open and node.children_state == "unloaded" then
      ctx.scanner:scan(node.id, function()
        vim.schedule(function()
          refresh_preserving(ctx)
        end)
      end)
    else
      refresh_preserving(ctx)
    end
  else
    local target_win = ctx.window:get_target_winid()
    if target_win then
      vim.api.nvim_set_current_win(target_win)
      vim.cmd.edit(vim.fn.fnameescape(node.path))
    end
    if should_close_on_select(ctx) then
      get_eda().close()
    end
  end
end, { desc = "Open file or toggle directory" })

action.register("select_split", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node or Node.is_dir(node) then
    return
  end
  local target_win = ctx.window:get_target_winid()
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.cmd.split(vim.fn.fnameescape(node.path))
  if should_close_on_select(ctx) then
    get_eda().close()
  end
end, { desc = "Open file in horizontal split" })

action.register("select_vsplit", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node or Node.is_dir(node) then
    return
  end
  local target_win = ctx.window:get_target_winid()
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.cmd.vsplit(vim.fn.fnameescape(node.path))
  if should_close_on_select(ctx) then
    get_eda().close()
  end
end, { desc = "Open file in vertical split" })

action.register("select_tab", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node or Node.is_dir(node) then
    return
  end
  if should_close_on_select(ctx) then
    get_eda().close()
  end
  vim.cmd.tabedit(vim.fn.fnameescape(node.path))
end, { desc = "Open file in new tab" })

action.register("close", function()
  get_eda().close()
end, { desc = "Close explorer" })

action.register("parent", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end

  -- Top-level node: navigate to parent directory
  if not node.parent_id or node.parent_id == ctx.store.root_id then
    navigate_to_parent_root(ctx)
    return
  end

  -- Non-root: move cursor to parent directory
  if node.parent_id then
    ctx.buffer.target_node_id = node.parent_id
    if ctx.explorer._refresh_for_navigation then
      ctx.explorer._refresh_for_navigation()
    else
      ctx.buffer:render(ctx.store)
    end
  end
end, { desc = "Navigate to parent directory" })

action.register("cwd", function(ctx)
  get_eda()._change_root(ctx.explorer, vim.fn.getcwd())
end, { desc = "Change root to cwd" })

action.register("cd", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node or not Node.is_dir(node) then
    return
  end
  get_eda()._change_root(ctx.explorer, node.path)
end, { desc = "Change root to directory" })

action.register("collapse_all", function(ctx)
  local capture = nil
  if vim.bo[ctx.buffer.bufnr].modified then
    local edit_preserve = require("eda.buffer.edit_preserve")
    local cfg = ctx.config
    capture =
      edit_preserve.capture(ctx.buffer.bufnr, ctx.buffer.painter, ctx.store, ctx.explorer.root_path, cfg.indent.width)
    -- Keep directories (and their ancestors) that contain edits open
    local keep_open = {}
    for _, op in ipairs(capture.operations) do
      for _, p in ipairs({ op.path, op.src }) do
        if p then
          local ancestor = vim.fn.fnamemodify(p, ":h")
          while ancestor and ancestor ~= "" do
            keep_open[ancestor] = true
            local next_a = vim.fn.fnamemodify(ancestor, ":h")
            if next_a == ancestor then
              break
            end
            ancestor = next_a
          end
        end
      end
    end
    local kept_count = 0
    for _, node in pairs(ctx.store.nodes) do
      if Node.is_dir(node) and node.id ~= ctx.store.root_id then
        if keep_open[node.path] then
          kept_count = kept_count + 1
        else
          node.open = false
        end
      end
    end
    if kept_count > 0 then
      vim.notify("eda: " .. kept_count .. " directories kept open (contain edits)", vim.log.levels.INFO)
    end
  else
    for _, node in pairs(ctx.store.nodes) do
      if Node.is_dir(node) and node.id ~= ctx.store.root_id then
        node.open = false
      end
    end
  end
  refresh_preserving(ctx, capture)
end, { desc = "Collapse all directories" })

action.register("collapse_node", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  if Node.is_dir(node) and node.open then
    -- Check if collapsing would lose edits
    if vim.bo[ctx.buffer.bufnr].modified then
      local edit_preserve = require("eda.buffer.edit_preserve")
      local cfg = ctx.config
      local capture =
        edit_preserve.capture(ctx.buffer.bufnr, ctx.buffer.painter, ctx.store, ctx.explorer.root_path, cfg.indent.width)
      if has_edits_under(capture, node.path) then
        vim.notify("eda: save or discard changes in " .. node.name .. "/ before collapsing", vim.log.levels.WARN)
        return
      end
    end
    node.open = false
    ctx.explorer._incremental_hint = { toggled_node_id = node.id }
    refresh_preserving(ctx)
  elseif node.parent_id then
    local parent = ctx.store:get(node.parent_id)
    if parent and parent.id ~= ctx.store.root_id then
      -- Check if collapsing parent would lose edits
      if vim.bo[ctx.buffer.bufnr].modified then
        local edit_preserve = require("eda.buffer.edit_preserve")
        local cfg = ctx.config
        local capture = edit_preserve.capture(
          ctx.buffer.bufnr,
          ctx.buffer.painter,
          ctx.store,
          ctx.explorer.root_path,
          cfg.indent.width
        )
        if has_edits_under(capture, parent.path) then
          vim.notify("eda: save or discard changes in " .. parent.name .. "/ before collapsing", vim.log.levels.WARN)
          return
        end
      end
      parent.open = false
      ctx.buffer.target_node_id = parent.id
      ctx.explorer._incremental_hint = { toggled_node_id = parent.id }
      refresh_preserving(ctx)
    elseif parent then
      navigate_to_parent_root(ctx)
    end
  end
end, { desc = "Collapse node or go to parent" })

action.register("refresh", function(ctx)
  local util = require("eda.util")

  -- Clear modified flag so repaint is not suppressed
  vim.bo[ctx.buffer.bufnr].modified = false

  ctx.store:next_generation()
  ctx.scanner:rescan_preserving_state(ctx.store.root_id, function()
    vim.schedule(function()
      if not util.is_valid_buf(ctx.buffer.bufnr) then
        return
      end
      refresh(ctx)
    end)
  end)
end, { desc = "Refresh file tree" })

action.register("toggle_hidden", function(ctx)
  ctx.config.show_hidden = not ctx.config.show_hidden
  action.dispatch("refresh", ctx)
end, { desc = "Toggle hidden files" })

action.register("toggle_gitignored", function(ctx)
  ctx.config.show_gitignored = not ctx.config.show_gitignored
  refresh_preserving(ctx)
end, { desc = "Toggle gitignored files" })

---Merge ancestor dir paths of all reported changed files into open_dirs set.
---@param reported table<string, true>
---@param root string
---@return table<string, true>
local function collect_all_changed_ancestor_dirs(reported, root)
  local open_dirs = {}
  for path in pairs(reported) do
    local parent = path:match("^(.*)/[^/]*$")
    while parent and #parent > #root do
      open_dirs[parent] = true
      parent = parent:match("^(.*)/[^/]*$")
    end
  end
  return open_dirs
end

---Navigate to previous/next git-changed file across the entire tree.
---Pre-scans unloaded ancestors via scan_open_unloaded, then wraps around.
---@param ctx eda.ActionContext
---@param dir "next"|"prev"
local function navigate_git_change(ctx, dir)
  if ctx.config.git and ctx.config.git.enabled == false then
    return
  end

  local root = ctx.explorer.root_path
  local ready = git.get_status_ready(root)
  if ready == nil or ready == "loading" then
    vim.notify("eda: git status not ready", vim.log.levels.WARN)
    return
  end
  if ready == "no_repo" then
    vim.notify("eda: not a git repository", vim.log.levels.WARN)
    return
  end

  local reported = git.get_reported_changes(root)
  if not reported or not next(reported) then
    vim.notify("eda: no git changes")
    return
  end

  local open_dirs = collect_all_changed_ancestor_dirs(reported, root)

  ctx.scanner:scan_open_unloaded(open_dirs, function()
    vim.schedule(function()
      local util = require("eda.util")
      if not util.is_valid_buf(ctx.buffer.bufnr) then
        return
      end

      -- Re-flatten with should_descend so that closed-but-loaded ancestors are
      -- traversed. buffer.flat_lines is stale after scan_open_unloaded.
      local flat_lines = Flatten.flatten(ctx.store, ctx.store.root_id, {
        should_descend = function(node)
          return open_dirs[node.path] == true or node.open
        end,
      })

      local cursor_node = ctx.buffer:get_cursor_node(ctx.window.winid)
      local changed_indexes = {}
      local cursor_index
      for i, line in ipairs(flat_lines) do
        if reported[line.node.path] then
          changed_indexes[#changed_indexes + 1] = i
        end
        if cursor_node and line.node_id == cursor_node.id then
          cursor_index = i
        end
      end

      local target_index = find_next_change_index(changed_indexes, cursor_index, dir)
      if not target_index then
        vim.notify("eda: no visible git changes")
        return
      end

      local target = flat_lines[target_index]
      -- Expand ancestors (persistent: matches the "jump keeps dirs open" requirement)
      for _, ancestor in ipairs(ctx.store:ancestors(target.node_id)) do
        if Node.is_dir(ancestor) and ancestor.id ~= ctx.store.root_id then
          ancestor.open = true
        end
      end

      ctx.buffer.target_node_id = target.node_id
      ctx.explorer._refresh_for_navigation()
    end)
  end)
end

action.register("next_git_change", function(ctx)
  navigate_git_change(ctx, "next")
end, { desc = "Jump to next git change" })

action.register("prev_git_change", function(ctx)
  navigate_git_change(ctx, "prev")
end, { desc = "Jump to previous git change" })

action.register("toggle_git_changes", function(ctx)
  local root = ctx.explorer.root_path
  local ready = git.get_status_ready(root)
  if ready == "no_repo" then
    vim.notify("eda: not a git repository", vim.log.levels.WARN)
    return
  end

  ctx.config.show_only_git_changes = not ctx.config.show_only_git_changes
  -- Toggle changes the global visibility rules; force a full repaint.
  ctx.explorer._incremental_hint = nil

  if ctx.config.show_only_git_changes and ready == "ready" then
    -- Preload ancestors of changed files so force-descent reveals them
    local reported = git.get_reported_changes(root)
    if reported and next(reported) then
      local open_dirs = collect_all_changed_ancestor_dirs(reported, root)
      ctx.scanner:scan_open_unloaded(open_dirs, function()
        vim.schedule(function()
          local util = require("eda.util")
          if util.is_valid_buf(ctx.buffer.bufnr) then
            refresh_preserving(ctx)
          end
        end)
      end)
      return
    end
  end

  refresh_preserving(ctx)
end, { desc = "Toggle filter to show only git changes" })

action.register("yank_path", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  local rel = node.path:sub(#ctx.explorer.root_path + 2)
  vim.fn.setreg("+", rel)
  vim.notify("Yanked: " .. rel)
end, { desc = "Yank relative path" })

action.register("yank_path_absolute", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  vim.fn.setreg("+", node.path)
  vim.notify("Yanked: " .. node.path)
end, { desc = "Yank absolute path" })

action.register("yank_name", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  vim.fn.setreg("+", node.name)
  vim.notify("Yanked: " .. node.name)
end, { desc = "Yank file name" })

-- Phase 4 actions

action.register("expand_all", function(ctx)
  local target = ctx.store:get(ctx.store.root_id)
  if not target then
    return
  end
  -- Capture edits before tree changes so they can be replayed after re-render
  local capture = nil
  if vim.bo[ctx.buffer.bufnr].modified then
    local edit_preserve = require("eda.buffer.edit_preserve")
    local cfg = ctx.config
    capture =
      edit_preserve.capture(ctx.buffer.bufnr, ctx.buffer.painter, ctx.store, ctx.explorer.root_path, cfg.indent.width)
  end
  local max_depth = ctx.config.expand_depth
  target.open = true
  ctx.scanner:scan_recursive(target.id, max_depth, function()
    vim.schedule(function()
      -- Open all loaded directories
      local function open_all(nid, depth)
        if depth > max_depth then
          return
        end
        local n = ctx.store:get(nid)
        if n and Node.is_dir(n) and n.children_state == "loaded" then
          n.open = true
          if n.children_ids then
            for _, cid in ipairs(n.children_ids) do
              open_all(cid, depth + 1)
            end
          end
        end
      end
      open_all(target.id, 0)
      refresh_preserving(ctx, capture)
    end)
  end)
end, { desc = "Expand all directories" })

action.register("expand_recursive", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  local target = Node.is_dir(node) and node or (node.parent_id and ctx.store:get(node.parent_id))
  if not target or not Node.is_dir(target) then
    return
  end
  local max_depth = ctx.config.expand_depth
  target.open = true
  ctx.scanner:scan_recursive(target.id, max_depth, function()
    vim.schedule(function()
      local function open_all(nid, depth)
        if depth > max_depth then
          return
        end
        local n = ctx.store:get(nid)
        if n and Node.is_dir(n) and n.children_state == "loaded" then
          n.open = true
          if n.children_ids then
            for _, cid in ipairs(n.children_ids) do
              open_all(cid, depth + 1)
            end
          end
        end
      end
      open_all(target.id, 0)
      refresh_preserving(ctx)
    end)
  end)
end, { desc = "Expand directory recursively" })

action.register("collapse_recursive", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  local target = Node.is_dir(node) and node or (node.parent_id and ctx.store:get(node.parent_id))
  if not target or not Node.is_dir(target) then
    return
  end
  -- Check if collapsing would lose edits
  local capture = nil
  if vim.bo[ctx.buffer.bufnr].modified then
    local edit_preserve = require("eda.buffer.edit_preserve")
    local cfg = ctx.config
    capture =
      edit_preserve.capture(ctx.buffer.bufnr, ctx.buffer.painter, ctx.store, ctx.explorer.root_path, cfg.indent.width)
    if has_edits_under(capture, target.path) then
      vim.notify("eda: save or discard changes in " .. target.name .. "/ before collapsing", vim.log.levels.WARN)
      return
    end
  end
  local function close_all(nid)
    local n = ctx.store:get(nid)
    if n and Node.is_dir(n) then
      n.open = false
      if n.children_ids then
        for _, cid in ipairs(n.children_ids) do
          close_all(cid)
        end
      end
    end
  end
  close_all(target.id)
  ctx.buffer.target_node_id = target.id
  refresh_preserving(ctx, capture)
end, { desc = "Collapse directory recursively" })

action.register("mark_toggle", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  node._marked = not node._marked
  refresh(ctx)
  -- Move cursor down
  local cursor = vim.api.nvim_win_get_cursor(ctx.window.winid)
  local line_count = vim.api.nvim_buf_line_count(ctx.buffer.bufnr)
  if cursor[1] < line_count then
    vim.api.nvim_win_set_cursor(ctx.window.winid, { cursor[1] + 1, cursor[2] })
  end
end, { desc = "Toggle mark on node" })

action.register("mark_bulk_delete", function(ctx)
  local Fs = require("eda.fs")
  local Confirm = require("eda.buffer.confirm")
  local operations = {}
  for _, node in pairs(ctx.store.nodes) do
    if node._marked then
      table.insert(operations, {
        type = "delete",
        path = node.path,
        entry_type = Node.is_dir(node) and "directory" or "file",
      })
    end
  end
  if #operations == 0 then
    vim.notify("No marked nodes")
    return
  end
  Confirm.show(operations, ctx.explorer.root_path, function()
    Fs.execute_operations(operations, { delete_to_trash = ctx.config.delete_to_trash }, function(_result)
      vim.schedule(function()
        ctx.scanner:rescan_preserving_state(ctx.store.root_id, function()
          vim.schedule(function()
            refresh(ctx)
          end)
        end)
      end)
    end)
  end, function() end)
end, { desc = "Delete marked nodes" })

action.register("mark_bulk_move", function(ctx)
  local marked = {}
  for _, node in pairs(ctx.store.nodes) do
    if node._marked then
      table.insert(marked, node)
    end
  end
  if #marked == 0 then
    vim.notify("No marked nodes")
    return
  end
  -- Prompt for destination directory
  vim.ui.input({ prompt = "Move to directory: ", default = ctx.explorer.root_path .. "/" }, function(input)
    if not input or input == "" then
      return
    end
    local Fs = require("eda.fs")
    local Confirm = require("eda.buffer.confirm")
    local dest = input:gsub("/+$", "")
    local operations = {}
    for _, node in ipairs(marked) do
      table.insert(operations, {
        type = "move",
        src = node.path,
        dst = dest .. "/" .. node.name,
        path = dest .. "/" .. node.name,
      })
    end
    Confirm.show(operations, ctx.explorer.root_path, function()
      Fs.execute_operations(operations, { delete_to_trash = false }, function(result)
        vim.schedule(function()
          if not result.error then
            ctx.scanner:rescan_preserving_state(ctx.store.root_id, function()
              vim.schedule(function()
                refresh(ctx)
              end)
            end)
          end
        end)
      end)
    end, function() end)
  end)
end, { desc = "Move marked nodes" })

--- Generate a copy name for a file (e.g., "file.txt" → "file_copy.txt", ".gitignore" → ".gitignore_copy")
---@param name string
---@return string
local function generate_copy_name(name)
  local ext = name:match("%.([^%.]+)$") or ""
  local base = ext ~= "" and name:sub(1, -(#ext + 2)) or name
  if base == "" or base == "." then
    return name .. "_copy"
  end
  if ext ~= "" then
    return base .. "_copy." .. ext
  end
  return base .. "_copy"
end

action.register("duplicate", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node or Node.is_dir(node) then
    return
  end
  local new_name = generate_copy_name(node.name)
  local dir = vim.fn.fnamemodify(node.path, ":h")

  vim.ui.input({ prompt = "Duplicate as: ", default = new_name }, function(input)
    if not input or input == "" then
      return
    end
    local Fs = require("eda.fs")
    Fs.copy(node.path, dir .. "/" .. input, function(err)
      if err then
        vim.notify(err, vim.log.levels.ERROR)
        return
      end
      ctx.scanner:rescan_preserving_state(ctx.store.root_id, function()
        vim.schedule(function()
          refresh(ctx)
        end)
      end)
    end)
  end)
end, { desc = "Duplicate file" })

action.register("system_open", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if not node then
    return
  end
  local sysname = vim.uv.os_uname().sysname
  local cmd = sysname == "Darwin" and "open" or "xdg-open"
  vim.system({ cmd, node.path })
end, { desc = "Open with system application" })

action.register("toggle_preview", function(ctx)
  local preview = ctx.explorer.preview
  local cfg = ctx.config.preview
  cfg.enabled = not cfg.enabled
  if cfg.enabled then
    local node = ctx.buffer:get_cursor_node(ctx.window.winid)
    preview:update(node)
  else
    preview:close()
  end
end, { desc = "Toggle file preview" })

action.register("preview_scroll_down", function(ctx)
  local preview = ctx.explorer.preview
  if not preview:scroll_down() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-f>", true, false, true), "n", false)
  end
end, { desc = "Scroll preview down (half page)" })

action.register("preview_scroll_up", function(ctx)
  local preview = ctx.explorer.preview
  if not preview:scroll_up() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-b>", true, false, true), "n", false)
  end
end, { desc = "Scroll preview up (half page)" })

action.register("preview_scroll_page_down", function(ctx)
  local preview = ctx.explorer.preview
  preview:scroll_page_down()
end, { desc = "Scroll preview down (full page)" })

action.register("preview_scroll_page_up", function(ctx)
  local preview = ctx.explorer.preview
  preview:scroll_page_up()
end, { desc = "Scroll preview up (full page)" })

action.register("inspect", function(ctx)
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  if node then
    vim.print(node)
  end
end, { desc = "Inspect node data" })

-- Helper: get nodes from visual selection or cursor node.
---@param ctx eda.ActionContext
---@return eda.TreeNode[]
local function get_selected_nodes(ctx)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    local start_line = vim.fn.line("'<")
    local end_line = vim.fn.line("'>")
    local header_lines = ctx.buffer.painter.header_lines or 0
    local nodes = {}
    for line = start_line, end_line do
      local fl = ctx.buffer.flat_lines[line - header_lines]
      if fl then
        local node = ctx.store:get(fl.node_id)
        if node and node.id ~= ctx.store.root_id then
          table.insert(nodes, node)
        end
      end
    end
    return nodes
  else
    local node = ctx.buffer:get_cursor_node(ctx.window.winid)
    if node and node.id ~= ctx.store.root_id then
      return { node }
    end
    return {}
  end
end

action.register("cut", function(ctx)
  local register = require("eda.register")
  local nodes = get_selected_nodes(ctx)
  if #nodes == 0 then
    return
  end
  local paths = {}
  for _, node in ipairs(nodes) do
    table.insert(paths, node.path)
  end
  register.set(paths, "cut")
  vim.notify("Cut " .. #paths .. " item(s)")
  refresh(ctx)
end, { desc = "Cut selected nodes" })

action.register("copy", function(ctx)
  local register = require("eda.register")
  local nodes = get_selected_nodes(ctx)
  if #nodes == 0 then
    return
  end
  local paths = {}
  for _, node in ipairs(nodes) do
    table.insert(paths, node.path)
  end
  register.set(paths, "copy")
  vim.notify("Copied " .. #paths .. " item(s)")
end, { desc = "Copy selected nodes" })

action.register("paste", function(ctx)
  local register = require("eda.register")
  local Fs = require("eda.fs")
  local reg = register.get()
  if not reg then
    vim.notify("Register is empty")
    return
  end
  -- Determine target directory
  local node = ctx.buffer:get_cursor_node(ctx.window.winid)
  local target_dir
  if node and Node.is_dir(node) then
    target_dir = node.path
  elseif node then
    target_dir = vim.fn.fnamemodify(node.path, ":h")
  else
    target_dir = ctx.explorer.root_path
  end
  -- Check for self-paste (directory into itself)
  for _, src_path in ipairs(reg.paths) do
    if target_dir == src_path or target_dir:sub(1, #src_path + 1) == src_path .. "/" then
      vim.notify("Cannot paste into itself: " .. vim.fn.fnamemodify(src_path, ":t"), vim.log.levels.ERROR)
      return
    end
  end
  -- Execute operations
  local remaining = #reg.paths
  local errors = {}
  for _, src_path in ipairs(reg.paths) do
    local name = vim.fn.fnamemodify(src_path, ":t")
    local dst = target_dir .. "/" .. name
    -- Handle name collision
    if vim.uv.fs_stat(dst) then
      local copy_name = generate_copy_name(name)
      dst = target_dir .. "/" .. copy_name
      -- Determine extension from original name (with dotfile awareness)
      local orig_ext = name:match("%.([^%.]+)$") or ""
      local orig_base = orig_ext ~= "" and name:sub(1, -(#orig_ext + 2)) or name
      local is_dotfile = orig_base == "" or orig_base == "."
      local counter = 2
      while vim.uv.fs_stat(dst) do
        if is_dotfile or orig_ext == "" then
          dst = target_dir .. "/" .. copy_name .. "_" .. counter
        else
          local copy_no_ext = copy_name:sub(1, -(#orig_ext + 2))
          dst = target_dir .. "/" .. copy_no_ext .. "_" .. counter .. "." .. orig_ext
        end
        counter = counter + 1
      end
    end
    local function on_done(err)
      if err then
        table.insert(errors, err)
      end
      remaining = remaining - 1
      if remaining == 0 then
        if #errors == 0 then
          register.clear()
        end
        vim.schedule(function()
          if #errors > 0 then
            vim.notify(table.concat(errors, "\n"), vim.log.levels.ERROR)
          end
          -- Refresh all instances
          get_eda().refresh_all()
        end)
      end
    end
    if reg.operation == "cut" then
      Fs.move(src_path, dst, on_done)
    else
      Fs.copy(src_path, dst, on_done)
    end
  end
end, { desc = "Paste from register" })

action.register("help", function(ctx)
  local Help = require("eda.buffer.help")
  Help.show(ctx.config.mappings)
end, { desc = "Show keymap help" })

action.register("split", function(ctx)
  get_eda().open_split(ctx.explorer.root_path)
end, { desc = "Open split pane" })

action.register("vsplit", function(ctx)
  get_eda().open_vsplit(ctx.explorer.root_path)
end, { desc = "Open horizontal split pane" })

action.register("actions", function(ctx)
  local items = {}
  for _, name in ipairs(action.list()) do
    if name ~= "actions" then
      local entry = action.get_entry(name)
      table.insert(items, { name = name, desc = entry and entry.desc or "" })
    end
  end
  vim.ui.select(items, {
    prompt = "Actions",
    format_item = function(item)
      if item.desc ~= "" then
        return item.name .. " — " .. item.desc
      end
      return item.name
    end,
  }, function(selected)
    if selected then
      action.dispatch(selected.name, ctx)
    end
  end)
end, { desc = "Open action picker" })

---Setup builtin actions (called once on module load).
function M.setup()
  -- All actions are registered above via action.register at module load time
end

return M
