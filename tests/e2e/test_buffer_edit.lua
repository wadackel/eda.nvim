local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["buffer edit"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/hello.txt", "hello")
      e2e.create_file(tmp .. "/world.txt", "world")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["buffer edit"]["creates a file via buffer insert and :w"] = function()
  e2e.open_eda(child, tmp)

  -- Open a new line below the first entry and type a filename
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "new_file.txt")

  -- Write
  e2e.feed(child, ":w<CR>")

  -- Wait for the file to appear on disk
  local new_path = tmp .. "/new_file.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", new_path))

  -- Verify from outer Neovim as well
  MiniTest.expect.equality(vim.fn.filereadable(new_path), 1)
end

T["buffer edit"]["deletes a file via dd and :w"] = function()
  e2e.open_eda(child, tmp)

  local target_path = tmp .. "/hello.txt"

  -- Confirm the file exists before deletion
  MiniTest.expect.equality(vim.fn.filereadable(target_path), 1)

  -- Move cursor to hello.txt line and delete it
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("hello.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  e2e.feed(child, "dd")
  e2e.feed(child, ":w<CR>")

  -- Wait for the file to be removed from disk
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", target_path))
  MiniTest.expect.equality(vim.fn.filereadable(target_path), 0)
end

T["buffer edit"]["renames a file via text change and :w"] = function()
  e2e.open_eda(child, tmp)

  local old_path = tmp .. "/hello.txt"
  local new_path = tmp .. "/renamed.txt"

  -- Find hello.txt line and change the text
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("hello.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Select the entire line and replace it
  e2e.feed(child, "cc")
  e2e.feed_insert(child, "renamed.txt")

  e2e.feed(child, ":w<CR>")

  -- Wait for rename to complete
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil and vim.uv.fs_stat(%q) ~= nil", old_path, new_path))
  MiniTest.expect.equality(vim.fn.filereadable(old_path), 0)
  MiniTest.expect.equality(vim.fn.filereadable(new_path), 1)
end

T["buffer edit"]["deletes a directory via dd with confirm dialog"] = function()
  -- Stop the default child (uses confirm = false)
  e2e.stop(child)

  -- Spawn a fresh child with confirm = true
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = true,
      header = false,
    })
  ]]
  )

  -- Create a subdirectory as the deletion target
  local dir_path = tmp .. "/subdir"
  vim.fn.mkdir(dir_path, "p")
  e2e.create_file(dir_path .. "/inner.txt", "inner")

  e2e.open_eda(child, tmp)

  -- Find and position cursor on subdir/ line
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("subdir/") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Delete with dd and write
  e2e.feed(child, "dd")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("subdir/") then return false end
    end
    return true
  ]]
  )

  e2e.feed(child, ":w<CR>")

  -- Wait for confirm dialog to appear and have focus
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Confirm with y
  e2e.feed(child, "y")

  -- Wait for the directory to be removed from disk
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", dir_path))
  MiniTest.expect.equality(vim.fn.isdirectory(dir_path), 0)
end

return T
