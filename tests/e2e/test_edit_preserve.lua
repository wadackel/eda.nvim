local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["edit preserving repaint"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/dir_a")
      e2e.create_file(tmp .. "/dir_a/file_a.txt", "a")
      e2e.create_dir(tmp .. "/dir_b")
      e2e.create_file(tmp .. "/dir_b/file_b.txt", "b")
      e2e.create_file(tmp .. "/root.txt", "root")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

-- Helper: insert a new line after the first entry and type a filename
local function insert_new_entry(child_nvim)
  e2e.exec(child_nvim, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child_nvim, "o")
  e2e.feed_insert(child_nvim, "new_entry.txt")
end

-- Helper: find a line containing text and position cursor on it
local function move_to_line(child_nvim, text)
  e2e.wait_until(
    child_nvim,
    string.format(
      [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find(%q) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]],
      text
    )
  )
end

-- Helper: check if buffer contains a line matching text
local function buf_has_line(child_nvim, text)
  return e2e.exec(
    child_nvim,
    string.format(
      [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find(%q) then return true end
    end
    return false
  ]],
      text
    )
  )
end

T["edit preserving repaint"]["select toggle preserves inserted line"] = function()
  e2e.open_eda(child, tmp)

  -- Insert a new line
  insert_new_entry(child)

  -- Verify buffer is modified
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)

  -- Toggle dir_b (a different directory) open via select; wait for the full
  -- edit-preserve cycle (paint + replay) to complete.
  move_to_line(child, "dir_b/")
  e2e.expand_and_wait_for_render(child)

  -- The inserted new_entry.txt line should still exist
  MiniTest.expect.equality(buf_has_line(child, "new_entry.txt"), true)

  -- Buffer should still be modified
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)
end

T["edit preserving repaint"]["multiple consecutive creates preserve order"] = function()
  e2e.open_eda(child, tmp)

  -- Insert two new lines consecutively after root.txt
  move_to_line(child, "root.txt")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "first.txt")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "second.txt")

  -- Toggle dir_b open; wait for the full edit-preserve cycle (paint + replay).
  move_to_line(child, "dir_b/")
  e2e.expand_and_wait_for_render(child)

  -- Both lines should exist
  MiniTest.expect.equality(buf_has_line(child, "first.txt"), true)
  MiniTest.expect.equality(buf_has_line(child, "second.txt"), true)

  -- Order should be preserved: first.txt before second.txt
  local order = e2e.exec(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local first_row, second_row
    for i, l in ipairs(lines) do
      if l:find("first.txt") then first_row = i end
      if l:find("second.txt") then second_row = i end
    end
    if first_row and second_row then
      return first_row < second_row
    end
    return false
  ]]
  )
  MiniTest.expect.equality(order, true)
end

T["edit preserving repaint"]["select toggle preserves renamed line"] = function()
  e2e.open_eda(child, tmp)

  -- Rename root.txt to renamed.txt
  move_to_line(child, "root.txt")
  e2e.feed(child, "ciw")
  e2e.feed_insert(child, "renamed.txt")

  -- Toggle dir_b open; wait for the full edit-preserve cycle (paint + replay).
  move_to_line(child, "dir_b/")
  e2e.expand_and_wait_for_render(child)

  -- renamed.txt should still exist (not reverted to root.txt)
  MiniTest.expect.equality(buf_has_line(child, "renamed.txt"), true)
  MiniTest.expect.equality(buf_has_line(child, "root.txt"), false)
end

T["edit preserving repaint"]["select toggle preserves deleted line"] = function()
  e2e.open_eda(child, tmp)

  -- Delete root.txt line
  move_to_line(child, "root.txt")
  e2e.feed(child, "dd")

  -- Toggle dir_b open; wait for the full edit-preserve cycle (paint + replay).
  move_to_line(child, "dir_b/")
  e2e.expand_and_wait_for_render(child)

  -- root.txt should NOT reappear
  MiniTest.expect.equality(buf_has_line(child, "root.txt"), false)
end

-- expand_all/collapse_all edit-preserve logic is covered by unit tests
-- in tests/buffer/test_edit_preserve.lua.

T["edit preserving repaint"]["save after toggle works correctly"] = function()
  e2e.open_eda(child, tmp)

  -- Insert a new file
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "created.txt")

  -- Toggle a directory to trigger edit-preserving repaint; wait for the full cycle.
  move_to_line(child, "dir_b/")
  e2e.expand_and_wait_for_render(child)

  -- Save — should create the file on disk
  e2e.feed(child, ":w<CR>")

  local new_path = tmp .. "/created.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", new_path))
  MiniTest.expect.equality(vim.fn.filereadable(new_path), 1)
end

T["edit preserving repaint"]["insert after collapsed dir then expand that dir places entry after children"] = function()
  e2e.open_eda(child, tmp)

  -- Insert a new line after dir_a/ (which starts collapsed)
  move_to_line(child, "dir_a/")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "new_entry.txt")

  -- Expand dir_a/; wait for the full edit-preserve cycle (paint + replay).
  move_to_line(child, "dir_a/")
  e2e.expand_and_wait_for_render(child)

  -- new_entry.txt should still exist
  MiniTest.expect.equality(buf_has_line(child, "new_entry.txt"), true)

  -- new_entry.txt should appear AFTER file_a.txt (not between dir_a/ and file_a.txt)
  local order = e2e.exec(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local file_a_row, new_entry_row
    for i, l in ipairs(lines) do
      if l:find("file_a.txt") then file_a_row = i end
      if l:find("new_entry.txt") then new_entry_row = i end
    end
    if file_a_row and new_entry_row then
      return new_entry_row > file_a_row
    end
    return false
  ]]
  )
  MiniTest.expect.equality(order, true)
end

T["edit preserving repaint"]["clean buffer operations work as before"] = function()
  e2e.open_eda(child, tmp)

  -- Buffer should not be modified
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), false)

  -- Toggle dir_a open
  move_to_line(child, "dir_a/")
  e2e.feed(child, "<CR>")

  -- file_a.txt should appear
  e2e.wait_for_node_loaded(child, tmp .. "/dir_a")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("file_a.txt") then return true end
    end
    return false
  ]]
  )

  -- Toggle dir_a closed
  move_to_line(child, "dir_a/")
  e2e.feed(child, "<CR>")

  -- file_a.txt should disappear from the rendered snapshot (dir_a now collapsed).
  e2e.wait_until(
    child,
    string.format(
      [[
    local explorer = require("eda").get_current()
    local snap = explorer.buffer.painter:get_snapshot()
    for _, entry in pairs(snap.entries or {}) do
      if entry.path == %q then return false end
    end
    return true
  ]],
      tmp .. "/dir_a/file_a.txt"
    )
  )
end

return T
