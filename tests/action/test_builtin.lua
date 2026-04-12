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

-- mark_toggle: flips _marked on cursor node
T["mark_toggle toggles _marked on cursor node"] = function()
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
  MiniTest.expect.equality(node._marked, false)

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

return T
