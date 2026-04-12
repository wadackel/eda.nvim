local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["navigation"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/sub")
      e2e.create_file(tmp .. "/sub/inner.txt", "inner")
      e2e.create_file(tmp .. "/root.txt", "root")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["navigation"]["parent on root closes and reopens at parent directory"] = function()
  -- Open eda at the sub directory
  local sub_dir = tmp .. "/sub"
  e2e.open_eda(child, sub_dir)

  -- Cursor should be on inner.txt (only entry in sub/)
  -- Press ^ to go to parent — since cursor is on root, it should close+reopen at tmp
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "^")

  -- Wait for the tree to reload with the parent directory content
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]],
    10000
  )

  -- The buffer should now show root.txt (from tmp, the parent)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("root.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["navigation"]["cd makes selected directory the new root"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to sub/ directory
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("sub/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- cd is not mapped by default, dispatch it via Lua
  e2e.exec(
    child,
    [[
    local action = require("eda.action")
    local eda = require("eda")
    local explorer = eda.get_current()
    local ctx = {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = require("eda.config").get(),
      explorer = explorer,
    }
    action.dispatch("cd", ctx)
  ]]
  )

  -- Wait for eda to reload with sub/ as root
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]],
    10000
  )

  -- Should show inner.txt (contents of sub/)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("inner.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["navigation"]["collapse_recursive moves cursor to collapsed directory from nested file"] = function()
  -- Create deeper nesting for this test
  e2e.create_dir(tmp .. "/sub/deep")
  e2e.create_file(tmp .. "/sub/deep/nested.txt", "nested")

  e2e.open_eda(child, tmp)

  -- Expand all directories
  e2e.feed(child, "gE")

  -- Wait for nested.txt to appear
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("nested.txt") then return true end
    end
    return false
  ]]
  )

  -- Move cursor to nested.txt
  e2e.exec(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("nested.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
    end
  ]]
  )

  -- Press W to collapse recursively
  e2e.feed(child, "W")

  -- Cursor should move to the parent directory (deep/)
  e2e.wait_until(
    child,
    [[
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    return line ~= nil and line:find("deep/") ~= nil
  ]]
  )
end

T["navigation"]["collapse_recursive keeps cursor on directory when already on directory"] = function()
  e2e.open_eda(child, tmp)

  -- Expand all
  e2e.feed(child, "gE")

  -- Wait for inner.txt to appear (sub/ is expanded)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("inner.txt") then return true end
    end
    return false
  ]]
  )

  -- Move cursor to sub/ directory
  e2e.exec(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("sub/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return
      end
    end
  ]]
  )

  -- Press W to collapse recursively
  e2e.feed(child, "W")

  -- Cursor should stay on sub/ directory
  e2e.wait_until(
    child,
    [[
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
    return line ~= nil and line:find("sub/") ~= nil
  ]]
  )
end

T["navigation"]["cwd makes CWD the new root"] = function()
  -- Set CWD to tmp
  e2e.exec(child, string.format("vim.cmd('cd %s')", tmp))

  -- Open eda at sub directory
  local sub_dir = tmp .. "/sub"
  e2e.open_eda(child, sub_dir)

  -- Press ~ for cwd
  e2e.feed(child, "~")

  -- Wait for eda to reload with CWD as root
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]],
    10000
  )

  -- Should show root.txt (from CWD = tmp)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("root.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["navigation"]["collapse_node navigates to parent directory at root boundary"] = function()
  -- Open eda at the sub directory
  local sub_dir = tmp .. "/sub"
  e2e.open_eda(child, sub_dir)

  -- Cursor should be on inner.txt (only entry in sub/)
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")

  -- Press <C-h> to collapse_node -- top-level node should navigate to parent
  e2e.feed(child, "\\<C-h>")

  -- Wait for the tree to reload with the parent directory content
  e2e.wait_until(child, string.format([[require("eda").get_all()[1].root_path == %q]], tmp), 10000)

  -- The buffer should now show root.txt (from tmp, the parent)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("root.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["navigation"]["parent at filesystem root does not navigate further"] = function()
  -- Open eda at filesystem root
  e2e.open_eda(child, "/")

  -- Press ^ -- should stay at / since there is no parent
  e2e.feed(child, "^")

  -- Small wait to ensure nothing breaks
  vim.uv.sleep(500)

  -- root_path should still be /
  local root_path = e2e.exec(child, [[return require("eda").get_all()[1].root_path]])
  MiniTest.expect.equality(root_path, "/")
end

T["navigation"]["cwd returns to original directory after parent navigation"] = function()
  -- Set CWD to sub directory
  local sub_dir = tmp .. "/sub"
  e2e.exec(child, string.format("vim.cmd('cd %s')", sub_dir))

  -- Open eda at sub directory
  e2e.open_eda(child, sub_dir)

  -- Navigate up with ^
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "^")

  -- Wait for navigation to parent
  e2e.wait_until(child, string.format([[require("eda").get_all()[1].root_path == %q]], tmp), 10000)

  -- Press ~ to return to cwd
  e2e.feed(child, "~")

  -- Wait for cwd root
  e2e.wait_until(child, string.format([[require("eda").get_all()[1].root_path == %q]], sub_dir), 10000)

  -- Should show inner.txt (from sub/)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("inner.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

return T
