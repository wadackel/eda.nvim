local action = require("eda.action")
local Store = require("eda.tree.store")
local Node = require("eda.tree.node")

-- Ensure builtin actions are loaded
require("eda.action.builtin")

local T = MiniTest.new_set()

--- Build a minimal mock context with a pre-populated store.
--- The store has:
---   root (id=1, /project, open=true, type=directory)
---     dir_a (id=2, /project/dir_a, open=true, type=directory)
---       file_a (id=3, /project/dir_a/file_a.lua, type=file)
---       sub_dir (id=4, /project/dir_a/sub_dir, open=true, type=directory)
---         file_b (id=5, /project/dir_a/sub_dir/file_b.lua, type=file)
---     dir_b (id=6, /project/dir_b, open=false, type=directory)
---     file_c (id=7, /project/file_c.lua, type=file)
---@param cursor_node_id integer? The node ID that get_cursor_node returns
---@return table ctx, eda.Store store
local function make_ctx(cursor_node_id)
  local store = Store.new()
  local root = store:set_root("/project")
  local dir_a =
    store:add({ name = "dir_a", path = "/project/dir_a", type = "directory", parent_id = root, open = true })
  store:add({ name = "file_a.lua", path = "/project/dir_a/file_a.lua", type = "file", parent_id = dir_a })
  local sub_dir =
    store:add({ name = "sub_dir", path = "/project/dir_a/sub_dir", type = "directory", parent_id = dir_a, open = true })
  store:add({ name = "file_b.lua", path = "/project/dir_a/sub_dir/file_b.lua", type = "file", parent_id = sub_dir })
  store:add({ name = "dir_b", path = "/project/dir_b", type = "directory", parent_id = root, open = false })
  store:add({ name = "file_c.lua", path = "/project/file_c.lua", type = "file", parent_id = root })

  -- Mark loaded
  store:get(root).children_state = "loaded"
  store:get(dir_a).children_state = "loaded"
  store:get(sub_dir).children_state = "loaded"

  local cursor_node = cursor_node_id and store:get(cursor_node_id) or nil

  -- Create a real scratch buffer for mock (needed by vim.bo[bufnr].modified)
  local mock_bufnr = vim.api.nvim_create_buf(false, true)

  local render_called = false
  local ctx = {
    store = store,
    buffer = {
      bufnr = mock_bufnr,
      get_cursor_node = function()
        return cursor_node
      end,
      render = function()
        render_called = true
      end,
      target_node_id = nil,
    },
    window = { winid = 1 },
    scanner = {
      scan = function(_, _, cb)
        if cb then
          cb()
        end
      end,
      scan_recursive = function(_, _, _, cb)
        if cb then
          cb()
        end
      end,
      rescan_preserving_state = function(_, _, cb)
        if cb then
          cb()
        end
      end,
    },
    config = {
      show_hidden = false,
      show_gitignored = false,
      expand_depth = 3,
    },
    explorer = {
      root_path = "/project",
    },
  }

  -- Expose render_called checker
  ctx._render_called = function()
    return render_called
  end

  return ctx, store
end

-- collapse_all: all directory nodes (except root) should have open=false
T["collapse_all closes all non-root directories"] = function()
  local ctx, store = make_ctx()
  action.dispatch("collapse_all", ctx)

  -- root should stay open
  MiniTest.expect.equality(store:get(store.root_id).open, true)
  -- dir_a (id=2) was open, should be closed
  MiniTest.expect.equality(store:get(2).open, false)
  -- sub_dir (id=4) was open, should be closed
  MiniTest.expect.equality(store:get(4).open, false)
  -- dir_b (id=6) was already closed, stays closed
  MiniTest.expect.equality(store:get(6).open, false)
end

-- collapse_node: open directory at cursor closes
T["collapse_node closes open directory at cursor"] = function()
  local ctx, store = make_ctx(2) -- cursor on dir_a (open)
  action.dispatch("collapse_node", ctx)
  MiniTest.expect.equality(store:get(2).open, false)
end

-- collapse_node: file at cursor targets parent
T["collapse_node on file closes parent directory"] = function()
  local ctx, store = make_ctx(3) -- cursor on file_a (parent is dir_a id=2)
  action.dispatch("collapse_node", ctx)
  MiniTest.expect.equality(store:get(2).open, false)
  MiniTest.expect.equality(ctx.buffer.target_node_id, 2)
end

-- collapse_node: does nothing if no cursor node
T["collapse_node does nothing without cursor node"] = function()
  local ctx, store = make_ctx(nil)
  action.dispatch("collapse_node", ctx)
  -- dir_a should still be open
  MiniTest.expect.equality(store:get(2).open, true)
end

-- collapse_recursive: DFS closes target and all descendants
T["collapse_recursive closes target and descendants"] = function()
  local ctx, store = make_ctx(2) -- cursor on dir_a
  action.dispatch("collapse_recursive", ctx)
  MiniTest.expect.equality(store:get(2).open, false)
  MiniTest.expect.equality(store:get(4).open, false) -- sub_dir
end

-- collapse_recursive: on a file, targets parent
T["collapse_recursive on file targets parent"] = function()
  local ctx, store = make_ctx(5) -- cursor on file_b (parent is sub_dir id=4)
  action.dispatch("collapse_recursive", ctx)
  MiniTest.expect.equality(store:get(4).open, false) -- sub_dir closed
end

-- toggle_hidden: flips show_hidden flag
T["toggle_hidden flips show_hidden"] = function()
  local ctx = make_ctx()

  -- Stub refresh (toggle_hidden dispatches "refresh" which requires rescan)
  ctx.scanner.rescan_preserving_state = function(_, _, cb)
    if cb then
      vim.schedule(function()
        cb()
      end)
    end
  end
  -- Override bufnr for vim.bo access
  local bufnr = vim.api.nvim_create_buf(false, true)
  ctx.buffer.bufnr = bufnr

  MiniTest.expect.equality(ctx.config.show_hidden, false)
  action.dispatch("toggle_hidden", ctx)
  MiniTest.expect.equality(ctx.config.show_hidden, true)
  action.dispatch("toggle_hidden", ctx)
  MiniTest.expect.equality(ctx.config.show_hidden, false)

  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- toggle_gitignored: flips show_gitignored flag
T["toggle_gitignored flips show_gitignored"] = function()
  local ctx = make_ctx()
  MiniTest.expect.equality(ctx.config.show_gitignored, false)
  action.dispatch("toggle_gitignored", ctx)
  MiniTest.expect.equality(ctx.config.show_gitignored, true)
  action.dispatch("toggle_gitignored", ctx)
  MiniTest.expect.equality(ctx.config.show_gitignored, false)
end

-- mark_toggle: cycles _marked between nil and true (2-value invariant)
T["mark_toggle cycles _marked between nil and true"] = function()
  local ctx, store = make_ctx(3) -- cursor on file_a

  -- mock win/buf APIs needed by mark_toggle
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line1", "line2", "line3" })
  local winid = vim.api.nvim_open_win(bufnr, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })
  ctx.window.winid = winid
  ctx.buffer.bufnr = bufnr

  local node = store:get(3)
  MiniTest.expect.equality(node._marked, nil)
  action.dispatch("mark_toggle", ctx)
  MiniTest.expect.equality(node._marked, true)
  action.dispatch("mark_toggle", ctx)
  MiniTest.expect.equality(node._marked, nil)
  action.dispatch("mark_toggle", ctx)
  MiniTest.expect.equality(node._marked, true)

  vim.api.nvim_win_close(winid, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- yank_path: relative path in "+" register
T["yank_path sets relative path to + register"] = function()
  local ctx = make_ctx(3) -- file_a at /project/dir_a/file_a.lua
  local captured_reg, captured_val
  local orig_setreg = vim.fn.setreg
  vim.fn.setreg = function(reg, val)
    captured_reg = reg
    captured_val = val
    return orig_setreg(reg, val)
  end
  action.dispatch("yank_path", ctx)
  vim.fn.setreg = orig_setreg
  MiniTest.expect.equality(captured_reg, "+")
  MiniTest.expect.equality(captured_val, "dir_a/file_a.lua")
end

-- yank_path_absolute: absolute path in "+" register
T["yank_path_absolute sets absolute path to + register"] = function()
  local ctx = make_ctx(3)
  local captured_reg, captured_val
  local orig_setreg = vim.fn.setreg
  vim.fn.setreg = function(reg, val)
    captured_reg = reg
    captured_val = val
    return orig_setreg(reg, val)
  end
  action.dispatch("yank_path_absolute", ctx)
  vim.fn.setreg = orig_setreg
  MiniTest.expect.equality(captured_reg, "+")
  MiniTest.expect.equality(captured_val, "/project/dir_a/file_a.lua")
end

-- yank_name: filename only in "+" register
T["yank_name sets filename to + register"] = function()
  local ctx = make_ctx(3)
  local captured_reg, captured_val
  local orig_setreg = vim.fn.setreg
  vim.fn.setreg = function(reg, val)
    captured_reg = reg
    captured_val = val
    return orig_setreg(reg, val)
  end
  action.dispatch("yank_name", ctx)
  vim.fn.setreg = orig_setreg
  MiniTest.expect.equality(captured_reg, "+")
  MiniTest.expect.equality(captured_val, "file_a.lua")
end

-- yank_path: does nothing if no cursor node
T["yank_path does nothing without cursor node"] = function()
  local ctx = make_ctx(nil)
  local setreg_called = false
  local orig_setreg = vim.fn.setreg
  vim.fn.setreg = function(reg, val)
    setreg_called = true
    return orig_setreg(reg, val)
  end
  action.dispatch("yank_path", ctx)
  vim.fn.setreg = orig_setreg
  MiniTest.expect.equality(setreg_called, false)
end

-- find_next_change_index pure function tests (Task 3)

local builtin = require("eda.action.builtin")
local find_next = builtin._find_next_change_index

T["find_next_change_index: next advance"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 5, "next"), 8)
end

T["find_next_change_index: next wraps to first when past end"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 8, "next"), 2)
end

T["find_next_change_index: next from position before first"] = function()
  MiniTest.expect.equality(find_next({ 5, 8, 12 }, 3, "next"), 5)
end

T["find_next_change_index: next from position after last wraps"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 10, "next"), 2)
end

T["find_next_change_index: prev retreat"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 5, "prev"), 2)
end

T["find_next_change_index: prev wraps to last when before first"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 2, "prev"), 8)
end

T["find_next_change_index: prev from position after last"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 10, "prev"), 8)
end

T["find_next_change_index: prev from position before first wraps"] = function()
  MiniTest.expect.equality(find_next({ 5, 8, 12 }, 3, "prev"), 12)
end

T["find_next_change_index: empty list returns nil"] = function()
  MiniTest.expect.equality(find_next({}, 5, "next"), nil)
  MiniTest.expect.equality(find_next({}, 5, "prev"), nil)
  MiniTest.expect.equality(find_next({}, nil, "next"), nil)
end

T["find_next_change_index: single entry always returns it"] = function()
  MiniTest.expect.equality(find_next({ 7 }, nil, "next"), 7)
  MiniTest.expect.equality(find_next({ 7 }, 3, "next"), 7)
  MiniTest.expect.equality(find_next({ 7 }, 7, "next"), 7)
  MiniTest.expect.equality(find_next({ 7 }, 10, "prev"), 7)
end

T["find_next_change_index: cursor_index=nil returns first for next"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, nil, "next"), 2)
end

T["find_next_change_index: cursor_index=nil returns last for prev"] = function()
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, nil, "prev"), 8)
end

T["find_next_change_index: next skips cursor_index itself"] = function()
  -- When cursor is exactly on a changed line, next/prev should move past it
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 2, "next"), 5)
  MiniTest.expect.equality(find_next({ 2, 5, 8 }, 8, "prev"), 5)
end

-- ===============================================================
-- _get_target_nodes / _clear_marks / _resolve_unique_dst tests
-- ===============================================================

-- Build a ctx with flat_lines and painter.header_lines, needed by _get_target_nodes for Visual branch.
-- The flat_lines mirrors a fully-expanded tree:
--   line 1: dir_a       (id=2)
--   line 2: file_a.lua  (id=3)
--   line 3: sub_dir     (id=4)
--   line 4: file_b.lua  (id=5)
--   line 5: dir_b       (id=6)
--   line 6: file_c.lua  (id=7)
local function make_target_ctx(cursor_node_id)
  local ctx, store = make_ctx(cursor_node_id)
  ctx.buffer.flat_lines = {
    { node_id = 2 },
    { node_id = 3 },
    { node_id = 4 },
    { node_id = 5 },
    { node_id = 6 },
    { node_id = 7 },
  }
  ctx.buffer.painter = { header_lines = 0 }
  return ctx, store
end

-- Mock vim.fn.mode / vim.fn.line / nvim_feedkeys for Visual range simulation.
local function with_visual_range(mode, start_line, end_line, fn)
  local orig_mode = vim.fn.mode
  local orig_line = vim.fn.line
  local orig_feedkeys = vim.api.nvim_feedkeys
  local orig_replace = vim.api.nvim_replace_termcodes
  vim.fn.mode = function()
    return mode
  end
  vim.fn.line = function(expr)
    if expr == "'<" then
      return start_line
    end
    if expr == "'>" then
      return end_line
    end
    return orig_line(expr)
  end
  vim.api.nvim_feedkeys = function() end
  vim.api.nvim_replace_termcodes = function(keys)
    return keys
  end
  local ok, err = pcall(fn)
  vim.fn.mode = orig_mode
  vim.fn.line = orig_line
  vim.api.nvim_feedkeys = orig_feedkeys
  vim.api.nvim_replace_termcodes = orig_replace
  if not ok then
    error(err)
  end
end

local get_target = builtin._get_target_nodes
local clear_marks = builtin._clear_marks
local resolve_dst = builtin._resolve_unique_dst

T["_get_target_nodes: cursor single node, origin=cursor"] = function()
  local ctx = make_target_ctx(3) -- cursor on file_a
  local result = get_target(ctx)
  MiniTest.expect.equality(#result.nodes, 1)
  MiniTest.expect.equality(result.nodes[1].id, 3)
  MiniTest.expect.equality(result.origin, "cursor")
end

T["_get_target_nodes: cursor on root returns empty"] = function()
  local ctx, store = make_target_ctx(1)
  ctx.buffer.get_cursor_node = function()
    return store:get(store.root_id)
  end
  local result = get_target(ctx)
  MiniTest.expect.equality(#result.nodes, 0)
  MiniTest.expect.equality(result.origin, "empty")
end

T["_get_target_nodes: no cursor, no marks returns empty"] = function()
  local ctx = make_target_ctx(nil)
  local result = get_target(ctx)
  MiniTest.expect.equality(#result.nodes, 0)
  MiniTest.expect.equality(result.origin, "empty")
end

T["_get_target_nodes: marks return all marked nodes (root excluded)"] = function()
  local ctx, store = make_target_ctx(nil)
  store:get(3)._marked = true
  store:get(5)._marked = true
  store:get(6)._marked = true
  store:get(store.root_id)._marked = true
  local result = get_target(ctx)
  MiniTest.expect.equality(#result.nodes, 3)
  MiniTest.expect.equality(result.origin, "marks")
  for _, n in ipairs(result.nodes) do
    MiniTest.expect.equality(n.id ~= store.root_id, true)
  end
end

T["_get_target_nodes: visual range returns selected lines, origin=visual"] = function()
  local ctx = make_target_ctx(nil)
  local result
  with_visual_range("V", 2, 4, function()
    result = get_target(ctx)
  end)
  MiniTest.expect.equality(#result.nodes, 3)
  MiniTest.expect.equality(result.nodes[1].id, 3)
  MiniTest.expect.equality(result.nodes[2].id, 4)
  MiniTest.expect.equality(result.nodes[3].id, 5)
  MiniTest.expect.equality(result.origin, "visual")
end

T["_get_target_nodes: visual takes priority over marks"] = function()
  local ctx, store = make_target_ctx(nil)
  store:get(6)._marked = true
  store:get(7)._marked = true
  local result
  with_visual_range("v", 2, 3, function()
    result = get_target(ctx)
  end)
  MiniTest.expect.equality(result.origin, "visual")
  MiniTest.expect.equality(#result.nodes, 2)
  MiniTest.expect.equality(result.nodes[1].id, 3)
  MiniTest.expect.equality(result.nodes[2].id, 4)
end

T["_get_target_nodes: blockwise visual (<C-v>) also resolves as visual"] = function()
  local ctx = make_target_ctx(nil)
  local result
  -- "\22" is the raw key code for CTRL-V (U+0016); vim.fn.mode() returns it for blockwise Visual.
  with_visual_range("\22", 2, 3, function()
    result = get_target(ctx)
  end)
  MiniTest.expect.equality(result.origin, "visual")
  MiniTest.expect.equality(#result.nodes, 2)
  MiniTest.expect.equality(result.nodes[1].id, 3)
  MiniTest.expect.equality(result.nodes[2].id, 4)
end

T["_get_target_nodes: visual range excludes root"] = function()
  local ctx = make_target_ctx(nil)
  ctx.buffer.flat_lines = {
    { node_id = 1 },
    { node_id = 2 },
    { node_id = 3 },
  }
  local result
  with_visual_range("V", 1, 3, function()
    result = get_target(ctx)
  end)
  MiniTest.expect.equality(result.origin, "visual")
  MiniTest.expect.equality(#result.nodes, 2)
  MiniTest.expect.equality(result.nodes[1].id, 2)
  MiniTest.expect.equality(result.nodes[2].id, 3)
end

T["_clear_marks: resets all _marked to nil"] = function()
  local _, store = make_target_ctx(nil)
  store:get(3)._marked = true
  store:get(5)._marked = true
  store:get(6)._marked = true
  clear_marks(store)
  MiniTest.expect.equality(store:get(3)._marked, nil)
  MiniTest.expect.equality(store:get(5)._marked, nil)
  MiniTest.expect.equality(store:get(6)._marked, nil)
end

T["_clear_marks: no-op on already-clean store"] = function()
  local _, store = make_target_ctx(nil)
  clear_marks(store)
  MiniTest.expect.equality(store:get(3)._marked, nil)
end

-- _resolve_unique_dst tests use a real temp directory.
local helpers = require("helpers")

T["_resolve_unique_dst: returns path unchanged if no collision"] = function()
  local dir = helpers.create_temp_dir()
  local dst = resolve_dst(dir, "file.txt")
  MiniTest.expect.equality(dst, dir .. "/file.txt")
  helpers.remove_temp_dir(dir)
end

T["_resolve_unique_dst: appends _copy on first collision"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/file.txt", "")
  local dst = resolve_dst(dir, "file.txt")
  MiniTest.expect.equality(dst, dir .. "/file_copy.txt")
  helpers.remove_temp_dir(dir)
end

T["_resolve_unique_dst: uses _2, _3 for further collisions"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/file.txt", "")
  helpers.create_file(dir .. "/file_copy.txt", "")
  local dst1 = resolve_dst(dir, "file.txt")
  MiniTest.expect.equality(dst1, dir .. "/file_copy_2.txt")

  helpers.create_file(dir .. "/file_copy_2.txt", "")
  local dst2 = resolve_dst(dir, "file.txt")
  MiniTest.expect.equality(dst2, dir .. "/file_copy_3.txt")
  helpers.remove_temp_dir(dir)
end

T["_resolve_unique_dst: dotfile handling (.gitignore → .gitignore_copy)"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/.gitignore", "")
  local dst = resolve_dst(dir, ".gitignore")
  MiniTest.expect.equality(dst, dir .. "/.gitignore_copy")
  helpers.remove_temp_dir(dir)
end

T["_resolve_unique_dst: no-extension file (Makefile → Makefile_copy)"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/Makefile", "")
  local dst = resolve_dst(dir, "Makefile")
  MiniTest.expect.equality(dst, dir .. "/Makefile_copy")
  helpers.remove_temp_dir(dir)
end

T["_resolve_unique_dst: no-extension counter (Makefile, Makefile_copy → Makefile_copy_2)"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/Makefile", "")
  helpers.create_file(dir .. "/Makefile_copy", "")
  local dst = resolve_dst(dir, "Makefile")
  MiniTest.expect.equality(dst, dir .. "/Makefile_copy_2")
  helpers.remove_temp_dir(dir)
end

-- Regression: _resolve_unique_dst must match the inline logic currently in paste
-- (builtin.lua:901-918), which is what C1 will swap to use this helper.
T["_resolve_unique_dst: matches paste inline behavior (regression)"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/file.txt", "")
  helpers.create_file(dir .. "/file_copy.txt", "")

  local function paste_inline(target_dir, name)
    local dst = target_dir .. "/" .. name
    if vim.uv.fs_stat(dst) then
      local ext = name:match("%.([^%.]+)$") or ""
      local base = ext ~= "" and name:sub(1, -(#ext + 2)) or name
      local function gen()
        if base == "" or base == "." then
          return name .. "_copy"
        end
        if ext ~= "" then
          return base .. "_copy." .. ext
        end
        return base .. "_copy"
      end
      local copy_name = gen()
      dst = target_dir .. "/" .. copy_name
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
    return dst
  end

  for _, name in ipairs({ "file.txt", "other.md", ".gitignore", "Makefile" }) do
    local expected = paste_inline(dir, name)
    local actual = resolve_dst(dir, name)
    MiniTest.expect.equality(actual, expected)
  end
  helpers.remove_temp_dir(dir)
end

-- ────────────────────────────────────────────────────────────────────────────
-- quickfix action
-- ────────────────────────────────────────────────────────────────────────────

-- Close any quickfix window and wipe the quickfix list so each case starts clean.
local function qf_reset()
  pcall(vim.cmd, "cclose")
  vim.fn.setqflist({}, "f")
end

-- Entry guard: action must be registered. Falsey before Task 2 implementation.
T["quickfix action is registered"] = function()
  MiniTest.expect.equality(action.get_entry("quickfix") ~= nil, true)
end

-- Cursor fallback when no marks are set (unified Visual > marks > cursor rule).
T["quickfix action sets qflist from cursor when no marks"] = function()
  qf_reset()
  local ctx = make_ctx(3) -- cursor on file_a (/project/dir_a/file_a.lua)
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  local items = vim.fn.getqflist()
  MiniTest.expect.equality(#items, 1)
  MiniTest.expect.equality(vim.api.nvim_buf_get_name(items[1].bufnr), "/project/dir_a/file_a.lua")
  qf_reset()
end

-- Marks include 2 files + 1 directory; directory is skipped, files go into qflist,
-- and the user-facing notification is elevated to WARN so the skip is visible.
T["quickfix action sends marked files (directories skipped)"] = function()
  qf_reset()
  local ctx, store = make_ctx(nil)
  store:get(3)._marked = true -- file_a
  store:get(5)._marked = true -- file_b (under sub_dir)
  store:get(6)._marked = true -- dir_b (directory, must be skipped)
  ctx.config.quickfix = { auto_open = false }

  local notify_level
  local notify_msg
  local orig_notify = vim.notify
  vim.notify = function(msg, level)
    notify_msg = msg
    notify_level = level
  end
  action.dispatch("quickfix", ctx)
  vim.notify = orig_notify

  local items = vim.fn.getqflist()
  MiniTest.expect.equality(#items, 2)
  local names = {
    vim.api.nvim_buf_get_name(items[1].bufnr),
    vim.api.nvim_buf_get_name(items[2].bufnr),
  }
  table.sort(names)
  MiniTest.expect.equality(names[1], "/project/dir_a/file_a.lua")
  MiniTest.expect.equality(names[2], "/project/dir_a/sub_dir/file_b.lua")
  MiniTest.expect.equality(notify_level, vim.log.levels.WARN)
  MiniTest.expect.equality(notify_msg, "Quickfix: 2 file(s) (1 dir(s) skipped)")
  qf_reset()
end

-- All marked targets are directories: qflist must be left untouched.
T["quickfix action leaves qflist unchanged when all targets are directories"] = function()
  qf_reset()
  vim.fn.setqflist({}, " ", { title = "prior list", items = {} })
  local ctx, store = make_ctx(nil)
  store:get(2)._marked = true -- dir_a
  store:get(6)._marked = true -- dir_b
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  MiniTest.expect.equality(vim.fn.getqflist({ title = 0 }).title, "prior list")
  qf_reset()
end

-- No marks, no cursor, no visual: notify and noop; qflist unchanged.
T["quickfix action is no-op on empty target"] = function()
  qf_reset()
  vim.fn.setqflist({}, " ", { title = "prior list", items = {} })
  local ctx = make_ctx(nil) -- no cursor node
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  MiniTest.expect.equality(vim.fn.getqflist({ title = 0 }).title, "prior list")
  qf_reset()
end

-- Title is set to "eda marks".
T["quickfix action sets title to 'eda marks'"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  MiniTest.expect.equality(vim.fn.getqflist({ title = 0 }).title, "eda marks")
  qf_reset()
end

-- auto_open = true opens the quickfix window (observable via winid lookup).
T["quickfix action opens quickfix window when auto_open is true"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.config.quickfix = { auto_open = true }
  action.dispatch("quickfix", ctx)
  local winid = vim.fn.getqflist({ winid = 0 }).winid
  MiniTest.expect.equality(winid ~= 0, true)
  qf_reset()
end

-- auto_open = false leaves the quickfix window closed.
T["quickfix action does not open window when auto_open is false"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  MiniTest.expect.equality(vim.fn.getqflist({ winid = 0 }).winid, 0)
  qf_reset()
end

-- Defensive: malformed user config (`quickfix = false`) must not crash the action.
T["quickfix action tolerates quickfix config replaced with a non-table"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.config.quickfix = false -- simulates `setup({ quickfix = false })`
  action.dispatch("quickfix", ctx)
  -- qflist still populated, copen suppressed (no crash)
  MiniTest.expect.equality(#vim.fn.getqflist(), 1)
  MiniTest.expect.equality(vim.fn.getqflist({ winid = 0 }).winid, 0)
  qf_reset()
end

-- Marks are preserved after quickfix dispatch (non-destructive semantics).
T["quickfix action does not clear marks"] = function()
  qf_reset()
  local ctx, store = make_ctx(nil)
  store:get(3)._marked = true
  store:get(5)._marked = true
  ctx.config.quickfix = { auto_open = false }
  action.dispatch("quickfix", ctx)
  MiniTest.expect.equality(store:get(3)._marked, true)
  MiniTest.expect.equality(store:get(5)._marked, true)
  qf_reset()
end

-- Helper: stub eda.close and restore it after `fn` runs. Returns the invocation count.
local function with_eda_close_stub(fn)
  local eda = require("eda")
  local orig_close = eda.close
  local calls = 0
  eda.close = function()
    calls = calls + 1
  end
  local ok, err = pcall(fn)
  eda.close = orig_close
  if not ok then
    error(err)
  end
  return calls
end

-- Float + auto_open=true: close the float explorer before opening the quickfix
-- window to prevent the float from visually overlapping the qf split.
T["quickfix action closes float explorer before opening quickfix"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.window.kind = "float"
  ctx.config.quickfix = { auto_open = true }
  local close_calls = with_eda_close_stub(function()
    action.dispatch("quickfix", ctx)
  end)
  MiniTest.expect.equality(close_calls, 1)
  MiniTest.expect.equality(vim.fn.getqflist({ winid = 0 }).winid ~= 0, true)
  qf_reset()
end

-- Non-float window kinds must NOT auto-close the explorer — split_left/split_right/replace
-- do not visually overlap the bottom qf split.
T["quickfix action does not close explorer for non-float window kinds"] = function()
  for _, kind in ipairs({ "split_left", "split_right", "replace" }) do
    qf_reset()
    local ctx = make_ctx(3)
    ctx.window.kind = kind
    ctx.config.quickfix = { auto_open = true }
    local close_calls = with_eda_close_stub(function()
      action.dispatch("quickfix", ctx)
    end)
    MiniTest.expect.equality(close_calls, 0)
    qf_reset()
  end
end

-- Float + auto_open=false: neither close nor :copen should fire.
T["quickfix action does not close float when auto_open is false"] = function()
  qf_reset()
  local ctx = make_ctx(3)
  ctx.window.kind = "float"
  ctx.config.quickfix = { auto_open = false }
  local close_calls = with_eda_close_stub(function()
    action.dispatch("quickfix", ctx)
  end)
  MiniTest.expect.equality(close_calls, 0)
  MiniTest.expect.equality(vim.fn.getqflist({ winid = 0 }).winid, 0)
  qf_reset()
end

-- ===============================================================
-- _get_visual_targets (extracted from _get_target_nodes) + mark_clear_all
-- ===============================================================

local get_visual = builtin._get_visual_targets

T["_get_visual_targets: returns nil outside Visual mode"] = function()
  local ctx = make_target_ctx(nil)
  -- Default vim.fn.mode() returns "n" in headless tests
  local result = get_visual(ctx)
  MiniTest.expect.equality(result, nil)
end

T["_get_visual_targets: returns visual range nodes (root excluded)"] = function()
  local ctx = make_target_ctx(nil)
  ctx.buffer.flat_lines = {
    { node_id = 1 }, -- root
    { node_id = 2 },
    { node_id = 3 },
  }
  local result
  with_visual_range("V", 1, 3, function()
    result = get_visual(ctx)
  end)
  MiniTest.expect.equality(#result, 2)
  MiniTest.expect.equality(result[1].id, 2)
  MiniTest.expect.equality(result[2].id, 3)
end

T["mark_clear_all: clears all _marked to nil"] = function()
  local ctx, store = make_target_ctx(nil)
  store:get(3)._marked = true
  store:get(5)._marked = true
  store:get(6)._marked = true

  action.dispatch("mark_clear_all", ctx)

  MiniTest.expect.equality(store:get(3)._marked, nil)
  MiniTest.expect.equality(store:get(5)._marked, nil)
  MiniTest.expect.equality(store:get(6)._marked, nil)
  -- refresh must run when at least one mark was cleared
  MiniTest.expect.equality(ctx._render_called(), true)
end

T["mark_clear_all: no-op (no refresh) when no marks exist"] = function()
  local ctx, store = make_target_ctx(nil)
  -- No _marked set on any node
  action.dispatch("mark_clear_all", ctx)
  -- Store state unchanged
  MiniTest.expect.equality(store:get(3)._marked, nil)
  -- refresh must be skipped to avoid a pointless repaint
  MiniTest.expect.equality(ctx._render_called(), false)
end

return T
