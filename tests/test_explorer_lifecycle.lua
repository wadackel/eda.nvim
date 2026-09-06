local config = require("eda.config")
local eda = require("eda")
local helpers = require("helpers")

local T = MiniTest.new_set()

local tmp

local function setup(kind)
  config.setup({
    window = { kind = kind },
    preview = { enabled = false },
    git = { enabled = false },
    icon = { provider = "none" },
    header = false,
  })
  tmp = helpers.create_temp_dir()
  helpers.create_dir(tmp .. "/sub")
  helpers.create_file(tmp .. "/sub/file.txt", "FILE")
  -- Several rows so that "the cursor was restored" is distinguishable from
  -- "the cursor defaulted to the first row".
  helpers.create_file(tmp .. "/aaa.txt", "A")
  helpers.create_file(tmp .. "/zzz.txt", "Z")
  eda.open({ dir = tmp })
  helpers.wait_for(3000, function()
    local explorer = eda.get_current()
    return explorer ~= nil and explorer._initial_scan_complete
  end)
  return assert(eda.get_current(), "explorer was not created")
end

local function teardown()
  for _ = 1, 8 do
    if not eda.get_current() then
      break
    end
    eda.close()
  end
  assert(eda.get_current() == nil, "explorers were not released")
  vim.cmd("only")
  helpers.remove_temp_dir(tmp)
end

---@return boolean
local function augroup_exists(name)
  return (pcall(vim.api.nvim_get_autocmds, { group = name }))
end

local function option_autocmd_count()
  return #vim.api.nvim_get_autocmds({ event = "OptionSet", pattern = "modified" })
end

T["lifecycle"] = MiniTest.new_set({ hooks = { post_case = teardown } })

T["lifecycle"]["an externally closed split window releases its instance"] = function()
  local explorer = setup("split_left")
  local bufnr = explorer.buffer.bufnr

  vim.api.nvim_win_close(explorer.window.winid, true)
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)

  MiniTest.expect.equality(#eda.get_all(), 0)
  MiniTest.expect.equality(eda.get_current(), nil)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(bufnr), false)
end

-- A membership-guarded but synchronous handler passes the case above and fails this
-- one: an autocmd callback suppresses nested autocmds, so wiping the buffer inside
-- WinClosed never fires the BufWipeout hook that disposes the scanner and releases
-- the fs watchers.
T["lifecycle"]["an externally closed explorer releases its scanner, watchers and augroup"] = function()
  local explorer = setup("split_left")
  local bufnr = explorer.buffer.bufnr
  local scanner, watcher = explorer.scanner, explorer.watcher
  helpers.wait_for(2000, function()
    return next(watcher._handles) ~= nil
  end)
  MiniTest.expect.equality(next(watcher._handles) ~= nil, true)

  vim.api.nvim_win_close(explorer.window.winid, true)
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)

  MiniTest.expect.equality(scanner._disposed, true)
  MiniTest.expect.equality(next(watcher._handles), nil)
  MiniTest.expect.equality(augroup_exists("eda_explorer_" .. bufnr), false)
end

T["lifecycle"]["repeated open and external close does not accumulate global autocmds"] = function()
  local baseline = option_autocmd_count()
  for _ = 1, 3 do
    local explorer = setup("split_left")
    vim.api.nvim_win_close(explorer.window.winid, true)
    helpers.wait_for(2000, function()
      return #eda.get_all() == 0
    end)
    helpers.remove_temp_dir(tmp)
  end
  MiniTest.expect.equality(option_autocmd_count(), baseline)
end

-- The motivating symptom: the shared decoration provider stays armed on every redraw
-- for as long as a stale replace entry is listed.
T["lifecycle"]["the last replace explorer losing its window releases the geometry watcher"] = function()
  local explorer = setup("replace")
  MiniTest.expect.equality(augroup_exists("eda_geometry"), true)

  local other = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(explorer.window.winid, other)
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)

  MiniTest.expect.equality(#eda.get_all(), 0)
  MiniTest.expect.equality(augroup_exists("eda_geometry"), false)
end

T["lifecycle"]["destroying a non-current explorer leaves the current one alone"] = function()
  local first = setup("split_left")
  eda.open_split(tmp)
  helpers.wait_for(3000, function()
    return #eda.get_all() == 2
  end)
  local second = assert(eda.get_current(), "second explorer was not created")
  eda.open_split(tmp)
  helpers.wait_for(3000, function()
    return #eda.get_all() == 3
  end)
  local third = assert(eda.get_current(), "third explorer was not created")

  -- Focus the middle one, so "keep the current explorer" and "take the last instance"
  -- give different answers.
  vim.api.nvim_set_current_win(second.window.winid)
  MiniTest.expect.equality(eda.get_current(), second)

  eda.close(first)

  MiniTest.expect.equality(#eda.get_all(), 2)
  MiniTest.expect.equality(eda.get_current(), second)
  MiniTest.expect.equality(eda.get_all()[2], third)
end

T["lifecycle"]["closing an already destroyed explorer is a no-op"] = function()
  local first = setup("split_left")
  eda.open_split(tmp)
  helpers.wait_for(3000, function()
    return #eda.get_all() == 2
  end)
  local second = eda.get_current()

  eda.close(first)
  local before = eda.get_current()
  eda.close(first)

  MiniTest.expect.equality(#eda.get_all(), 1)
  MiniTest.expect.equality(eda.get_current(), before)
  MiniTest.expect.equality(eda.get_current(), second)
end

-- WinClosed fires before the window leaves the layout, so the cursor is still readable
-- there. Deferring the teardown without capturing it first silently drops the position
-- that reopening the same root is documented to restore.
T["lifecycle"]["an externally closed explorer still records its cursor position"] = function()
  local explorer = setup("split_left")
  local target = tmp .. "/zzz.txt"

  local row
  for i, fl in ipairs(explorer.buffer.flat_lines) do
    local node = explorer.store:get(fl.node_id)
    if node and node.path == target then
      row = i
    end
  end
  assert(row, "no row renders " .. target)
  vim.api.nvim_win_set_cursor(explorer.window.winid, { row, 0 })

  vim.api.nvim_win_close(explorer.window.winid, true)
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)

  eda.open({ dir = tmp })
  helpers.wait_for(3000, function()
    local reopened = eda.get_current()
    if not reopened or not reopened._initial_scan_complete then
      return false
    end
    local node = reopened.buffer:get_cursor_node(reopened.window.winid)
    return node ~= nil and node.path == target
  end)
  local reopened = assert(eda.get_current(), "explorer was not reopened")
  local node = reopened.buffer:get_cursor_node(reopened.window.winid)
  MiniTest.expect.equality(node and node.path, target)
end

-- A float too small to draw closes itself inside the VimResized callback, so the
-- WinClosed handler is suppressed there and the explorer would otherwise never be
-- released.
T["lifecycle"]["a float that shrinks below its minimum releases its instance"] = function()
  local explorer = setup("float")
  local bufnr = explorer.buffer.bufnr
  local saved = { columns = vim.o.columns, lines = vim.o.lines }

  vim.o.columns, vim.o.lines = 10, 4
  vim.api.nvim_exec_autocmds("VimResized", {})
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)
  vim.o.columns, vim.o.lines = saved.columns, saved.lines

  MiniTest.expect.equality(#eda.get_all(), 0)
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(bufnr), false)
  MiniTest.expect.equality(augroup_exists("eda_explorer_" .. bufnr), false)
end

-- The cursor hint exists only to survive a deferred teardown. A resize that leaves the
-- window open must not leave one behind, or closing later would restore the position the
-- cursor had at resize time instead of where it actually is.
T["lifecycle"]["a resize that keeps the window does not stale the saved cursor"] = function()
  local explorer = setup("split_left")

  local function row_of(path)
    for i, fl in ipairs(explorer.buffer.flat_lines) do
      local node = explorer.store:get(fl.node_id)
      if node and node.path == path then
        return i
      end
    end
    error("no row renders " .. path)
  end

  vim.api.nvim_win_set_cursor(explorer.window.winid, { row_of(tmp .. "/aaa.txt"), 0 })
  vim.api.nvim_exec_autocmds("VimResized", {})
  vim.api.nvim_win_set_cursor(explorer.window.winid, { row_of(tmp .. "/zzz.txt"), 0 })

  eda.close()
  helpers.wait_for(2000, function()
    return #eda.get_all() == 0
  end)

  eda.open({ dir = tmp })
  helpers.wait_for(3000, function()
    local reopened = eda.get_current()
    if not reopened or not reopened._initial_scan_complete then
      return false
    end
    local node = reopened.buffer:get_cursor_node(reopened.window.winid)
    return node ~= nil and node.path == tmp .. "/zzz.txt"
  end)
  local reopened = assert(eda.get_current(), "explorer was not reopened")
  local node = reopened.buffer:get_cursor_node(reopened.window.winid)
  MiniTest.expect.equality(node and node.path, tmp .. "/zzz.txt")
end

return T
