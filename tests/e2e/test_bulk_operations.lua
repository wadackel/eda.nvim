local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["bulk_operations"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      -- Register gM keymap for mark_bulk_move (no default binding)
      e2e.exec(
        child,
        [[
        vim.keymap.set("n", "gM", function()
          local eda = require("eda")
          local explorer = eda.get_current()
          if explorer then
            require("eda.action").dispatch("mark_bulk_move", {
              store = explorer.store,
              buffer = explorer.buffer,
              window = { winid = vim.api.nvim_get_current_win() },
              scanner = explorer.scanner,
              config = require("eda.config").get(),
              explorer = explorer,
            })
          end
        end, { buffer = false })
      ]]
      )
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/dest")
      e2e.create_file(tmp .. "/a.txt", "content_a")
      e2e.create_file(tmp .. "/b.txt", "content_b")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

-- BUG-4: mark_bulk_move default prompt creates double-slash in destination path
T["bulk_operations"]["mark_bulk_move default prompt avoids double slash"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to a.txt and mark it
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("a.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )
  e2e.feed(child, "m")

  -- Execute mark_bulk_move — accept default prompt (which has trailing /)
  e2e.feed(child, "gM")
  e2e.wait_until(child, 'vim.fn.mode() == "c"', 5000)
  e2e.feed(child, "<CR>")

  -- Wait for confirm dialog
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Confirm with y
  e2e.feed(child, "y")

  -- File should be moved to root (same directory since default is root/)
  -- The important thing: it should not error due to double-slash
  local expected_path = tmp .. "/a.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", expected_path), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(expected_path), 1)
end

-- Normal move: mark file and move to dest/ subdirectory
T["bulk_operations"]["mark_bulk_move moves file to specified directory"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to a.txt and mark it
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("a.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )
  e2e.feed(child, "m")

  -- Execute mark_bulk_move
  e2e.feed(child, "gM")
  e2e.wait_until(child, 'vim.fn.mode() == "c"', 5000)

  -- Clear the default input and type destination path
  e2e.feed(child, "<C-u>" .. tmp .. "/dest<CR>")

  -- Wait for confirm dialog
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Confirm with y
  e2e.feed(child, "y")

  local expected_path = tmp .. "/dest/a.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", expected_path), 10000)

  MiniTest.expect.equality(vim.fn.filereadable(expected_path), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a.txt"), 0)
end

-- Cancel: mark file, start move, then cancel — file stays
T["bulk_operations"]["mark_bulk_move cancel preserves files"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to a.txt and mark it
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("a.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )
  e2e.feed(child, "m")

  -- Execute mark_bulk_move then cancel
  e2e.feed(child, "gM")
  e2e.wait_until(child, 'vim.fn.mode() == "c"', 5000)
  e2e.feed(child, "<Esc>")

  -- Wait for normal mode
  e2e.wait_until(child, 'vim.fn.mode() == "n"', 3000)

  -- File should still be in original location
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a.txt"), 1)
end

-- Cancel at confirm dialog: mark file, enter destination, then reject confirm — file stays
T["bulk_operations"]["mark_bulk_move confirm cancel preserves files"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to a.txt and mark it
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("a.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )
  e2e.feed(child, "m")

  -- Execute mark_bulk_move and enter destination
  e2e.feed(child, "gM")
  e2e.wait_until(child, 'vim.fn.mode() == "c"', 5000)
  e2e.feed(child, "<C-u>" .. tmp .. "/dest<CR>")

  -- Wait for confirm dialog
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Reject with n
  e2e.feed(child, "n")

  -- Wait for normal mode (back to eda buffer)
  e2e.wait_until(child, 'vim.fn.mode() == "n"', 3000)

  -- File should still be in original location
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/dest/a.txt"), 0)
end

return T
