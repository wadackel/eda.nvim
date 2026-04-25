local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["clipboard"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/dest")
      e2e.create_file(tmp .. "/source.txt", "source content")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["clipboard"]["cut and paste moves file"] = function()
  e2e.open_eda(child, tmp)

  local src_path = tmp .. "/source.txt"
  local dst_path = tmp .. "/dest/source.txt"

  -- Move cursor to source.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("source.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Cut with gx
  e2e.feed(child, "gx")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp
  e2e.feed(child, "gp")

  -- Wait for file to be moved
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", dst_path), 10000)
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", src_path), 10000)

  MiniTest.expect.equality(vim.fn.filereadable(dst_path), 1)
  MiniTest.expect.equality(vim.fn.filereadable(src_path), 0)
end

T["clipboard"]["copy and paste copies file"] = function()
  e2e.open_eda(child, tmp)

  local src_path = tmp .. "/source.txt"
  local dst_path = tmp .. "/dest/source.txt"

  -- Move cursor to source.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("source.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Copy with gy
  e2e.feed(child, "gy")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp
  e2e.feed(child, "gp")

  -- Wait for file to be copied
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", dst_path), 10000)

  -- Both source and destination should exist
  MiniTest.expect.equality(vim.fn.filereadable(src_path), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst_path), 1)
end

T["clipboard"]["paste with name collision adds suffix"] = function()
  -- Create a file at dest that will collide
  e2e.create_file(tmp .. "/dest/source.txt", "existing")

  e2e.open_eda(child, tmp)

  -- Move cursor to source.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("source.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Copy with gy
  e2e.feed(child, "gy")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp — should create source_copy.txt due to collision
  e2e.feed(child, "gp")

  local collision_path = tmp .. "/dest/source_copy.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", collision_path), 10000)

  MiniTest.expect.equality(vim.fn.filereadable(collision_path), 1)
  -- Original dest file should still exist
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/dest/source.txt"), 1)
end

T["clipboard"]["duplicate creates file with _copy suffix"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to source.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("source.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press gd for duplicate — this opens vim.ui.input with default "source_copy.txt"
  -- We need to accept the default by pressing <CR>
  e2e.feed(child, "gd")
  -- Wait for the input prompt to appear
  e2e.wait_until(child, 'vim.fn.mode() == "c" or vim.fn.mode() == "n"', 3000)
  -- Accept default name
  e2e.feed(child, "<CR>")

  local dup_path = tmp .. "/source_copy.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", dup_path), 10000)

  MiniTest.expect.equality(vim.fn.filereadable(dup_path), 1)
  -- Original should still exist
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/source.txt"), 1)
end

-- BUG-1: paste clears register even when operations fail
T["clipboard"]["paste error preserves register"] = function()
  e2e.open_eda(child, tmp)

  -- Set register directly with a nonexistent source path
  e2e.exec(child, [[require("eda.register").set({"/tmp/nonexistent_eda_test_src"}, "copy")]])

  -- Hook vim.notify to detect paste completion
  e2e.exec(
    child,
    [[
    vim.g._eda_paste_done = false
    local orig_notify = vim.notify
    vim.notify = function(msg, ...)
      vim.g._eda_paste_done = true
      return orig_notify(msg, ...)
    end
  ]]
  )

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp — should fail because source doesn't exist
  e2e.feed(child, "gp")

  -- Wait for paste to complete (error notification fires)
  e2e.wait_until(child, "vim.g._eda_paste_done == true", 10000)

  -- Register should still be preserved after error
  local reg = e2e.exec(child, "return require('eda.register').get()")
  MiniTest.expect.no_equality(reg, vim.NIL)
end

-- BUG-2: paste collision overwrites existing _copy file when both source.txt and source_copy.txt exist
T["clipboard"]["paste does not overwrite existing _copy file"] = function()
  e2e.create_file(tmp .. "/dest/source.txt", "existing")
  e2e.create_file(tmp .. "/dest/source_copy.txt", "original_copy")
  e2e.open_eda(child, tmp)

  -- Move cursor to source.txt (the one in root, not in dest)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("source.txt") and not l:find("copy") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Copy with gy
  e2e.feed(child, "gy")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp — collision should NOT overwrite source_copy.txt
  e2e.feed(child, "gp")

  -- Wait for the paste to complete by observing register.clear() at the end of
  -- the on_done chain (lua/eda/action/builtin.lua:1169 — only runs after all
  -- copy callbacks land with no errors). This is more deterministic than a
  -- fixed sleep and avoids fs_stat (the renamed dst path is not predictable).
  e2e.wait_until(child, [[return require("eda.register").get() == nil]], 5000)

  -- The original source_copy.txt should still have "original_copy" content
  local content = vim.fn.readfile(tmp .. "/dest/source_copy.txt")
  MiniTest.expect.equality(content[1], "original_copy")
end

-- BUG-3: dotfile duplicate generates wrong name (.gitignore → _copy.gitignore instead of .gitignore_copy)
T["clipboard"]["duplicate dotfile generates correct name"] = function()
  e2e.create_file(tmp .. "/.gitignore", "# ignore")
  e2e.open_eda(child, tmp)

  -- Move cursor to .gitignore
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find(".gitignore", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Duplicate with gd → accept default name
  e2e.feed(child, "gd")
  e2e.wait_until(child, 'vim.fn.mode() == "c" or vim.fn.mode() == "n"', 3000)
  e2e.feed(child, "<CR>")

  -- Expected: .gitignore_copy (not _copy.gitignore)
  local expected_path = tmp .. "/.gitignore_copy"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", expected_path), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(expected_path), 1)
end

-- BUG-3: paste dotfile collision generates wrong suffix name
T["clipboard"]["paste dotfile collision generates correct suffix"] = function()
  e2e.create_file(tmp .. "/.gitignore", "source content")
  e2e.create_file(tmp .. "/dest/.gitignore", "dest content")
  e2e.open_eda(child, tmp)

  -- Move cursor to .gitignore
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find(".gitignore", 1, true) and not l:find("dest") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Copy with gy
  e2e.feed(child, "gy")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Move cursor to dest/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("dest/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Paste with gp — collision should produce .gitignore_copy
  e2e.feed(child, "gp")

  local expected_path = tmp .. "/dest/.gitignore_copy"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", expected_path), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(expected_path), 1)
end

T["clipboard"]["cut directory into itself is rejected"] = function()
  -- Create a directory with a file inside
  e2e.create_dir(tmp .. "/mydir")
  e2e.create_file(tmp .. "/mydir/child.txt", "child")
  e2e.open_eda(child, tmp)

  -- Expand all so mydir contents are visible
  e2e.feed(child, "gE")

  -- Move cursor to mydir/
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("mydir/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Cut with gx
  e2e.feed(child, "gx")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Hook vim.notify to capture error message
  e2e.exec(
    child,
    [[
    vim.g._eda_paste_error = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, level, ...)
      if level == vim.log.levels.ERROR then
        vim.g._eda_paste_error = msg
      end
      return orig_notify(msg, level, ...)
    end
  ]]
  )

  -- Cursor is already on mydir/ — paste into itself
  e2e.feed(child, "gp")

  -- Wait for error notification
  e2e.wait_until(child, "vim.g._eda_paste_error ~= nil", 5000)

  local err = e2e.exec(child, "return vim.g._eda_paste_error")
  MiniTest.expect.equality(type(err), "string")
  assert(err:find("Cannot paste into itself"), "Expected self-paste error, got: " .. tostring(err))

  -- Directory should still be in original location
  MiniTest.expect.equality(vim.fn.isdirectory(tmp .. "/mydir"), 1)
end

T["clipboard"]["copy directory into itself is rejected"] = function()
  -- Create a directory with a file inside
  e2e.create_dir(tmp .. "/mydir")
  e2e.create_file(tmp .. "/mydir/child.txt", "child")
  e2e.open_eda(child, tmp)

  -- Expand all so mydir contents are visible
  e2e.feed(child, "gE")

  -- Move cursor to mydir/
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("mydir/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Copy with gy
  e2e.feed(child, "gy")
  e2e.wait_until(child, [[require("eda.register").get() ~= nil]])

  -- Hook vim.notify to capture error message
  e2e.exec(
    child,
    [[
    vim.g._eda_paste_error = nil
    local orig_notify = vim.notify
    vim.notify = function(msg, level, ...)
      if level == vim.log.levels.ERROR then
        vim.g._eda_paste_error = msg
      end
      return orig_notify(msg, level, ...)
    end
  ]]
  )

  -- Cursor is already on mydir/ — paste into itself
  e2e.feed(child, "gp")

  -- Wait for error notification
  e2e.wait_until(child, "vim.g._eda_paste_error ~= nil", 5000)

  local err = e2e.exec(child, "return vim.g._eda_paste_error")
  MiniTest.expect.equality(type(err), "string")
  assert(err:find("Cannot paste into itself"), "Expected self-paste error, got: " .. tostring(err))

  -- No nested copy should have been created
  MiniTest.expect.equality(vim.fn.isdirectory(tmp .. "/mydir/mydir"), 0)
end

return T
