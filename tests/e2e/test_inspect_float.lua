local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

---Count windows whose buffer has filetype == "eda_inspect" in the child Neovim.
---@param child_ table
---@return integer
local function inspect_win_count(child_)
  return e2e.exec(
    child_,
    [[
    return (function()
      local n = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          n = n + 1
        end
      end
      return n
    end)()
  ]]
  )
end

---Return the concatenated lines of the inspect float buffer, or nil if none.
---@param child_ table
---@return string?
local function inspect_buf_text(child_)
  return e2e.exec(
    child_,
    [[
    return (function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          return table.concat(lines, "\n")
        end
      end
      return nil
    end)()
  ]]
  )
end

---Move the cursor in the eda buffer to the first line whose text matches the pattern.
---@param child_ table
---@param pattern string
local function cursor_to(child_, pattern)
  local row = e2e.exec(
    child_,
    string.format(
      [[
      return (function()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for i, line in ipairs(lines) do
          if line:find(%q) then
            vim.api.nvim_win_set_cursor(0, { i, 0 })
            return i
          end
        end
        return -1
      end)()
    ]],
      pattern
    )
  )
  assert(row and row > 0, "cursor_to: pattern not found: " .. pattern)
end

T["inspect float"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/sample.txt", string.rep("x", 2048))
      e2e.create_file(tmp .. "/other.txt", "hi")
      e2e.create_dir(tmp .. "/subdir")
      -- sample.link -> sample.txt
      vim.uv.fs_symlink(tmp .. "/sample.txt", tmp .. "/sample.link")
      -- dangling.link -> /nonexistent
      vim.uv.fs_symlink(tmp .. "/does-not-exist", tmp .. "/dangling.link")

      e2e.setup_eda(child)
      e2e.open_eda(child, tmp)
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["inspect float"]["A: <leader>i opens inspect float"] = function()
  cursor_to(child, "sample%.txt")
  MiniTest.expect.equality(inspect_win_count(child), 0)

  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )
  MiniTest.expect.equality(inspect_win_count(child), 1)
end

T["inspect float"]["B: <leader>i again closes inspect float (toggle)"] = function()
  cursor_to(child, "sample%.txt")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )

  -- Focus remains in the explorer; re-pressing <leader>i dispatches the inspect
  -- action again → toggle detects is_visible() and closes the float.
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 0",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )
  MiniTest.expect.equality(inspect_win_count(child), 0)
end

T["inspect float"]["C: CursorMoved updates float to new node (sticky)"] = function()
  local count_predicate = [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]

  cursor_to(child, "sample%.txt")
  e2e.feed(child, "\\i")
  e2e.wait_until(child, string.format("return (%s) == 1", count_predicate))

  local initial = inspect_buf_text(child)
  MiniTest.expect.no_equality(initial, nil)
  MiniTest.expect.equality(initial:find("sample%.txt") ~= nil, true)

  -- Sticky: cursor move refreshes the float in place instead of closing it.
  -- Use cursor_to (nvim_win_set_cursor) so the move lands synchronously via RPC.
  cursor_to(child, "other%.txt")
  e2e.wait_until(
    child,
    string.format(
      "return (%s)",
      [[(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then
        local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
        return text:find("other%.txt") ~= nil
      end
    end
    return false
  end)()]]
    )
  )

  -- Float must still be open after the cursor move.
  MiniTest.expect.equality(inspect_win_count(child), 1)
end

T["inspect float"]["D: symlink node shows Target line"] = function()
  cursor_to(child, "sample%.link")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )
  local text = inspect_buf_text(child)
  MiniTest.expect.no_equality(text, nil)
  MiniTest.expect.equality(text:find("Target") ~= nil, true)
end

T["inspect float"]["E: broken symlink shows broken"] = function()
  cursor_to(child, "dangling%.link")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )
  local text = inspect_buf_text(child)
  MiniTest.expect.no_equality(text, nil)
  MiniTest.expect.equality(text:find("broken") ~= nil, true)
end

T["inspect float"]["F: VimResized keeps the float visible"] = function()
  cursor_to(child, "sample%.txt")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )

  e2e.exec(child, 'return require("eda.buffer.inspect").reposition()')
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.buffer.inspect").is_visible()'), true)
end

T["inspect float"]["G: directory node inspect shows Entries"] = function()
  cursor_to(child, "subdir")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )
  local text = inspect_buf_text(child)
  MiniTest.expect.no_equality(text, nil)
  MiniTest.expect.equality(text:find("Entries") ~= nil, true)
end

T["inspect float"]["J: <C-w>w focuses the float and q closes it (safety net)"] = function()
  -- Regression guard: BufLeave on the eda buffer must NOT immediately close the
  -- inspect float when the user deliberately focuses it via <C-w>w.
  local count_predicate = [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]

  cursor_to(child, "sample%.txt")
  e2e.feed(child, "\\i")
  e2e.wait_until(child, string.format("return (%s) == 1", count_predicate))

  -- Switch focus to the inspect float via window API (synchronous RPC in headless).
  e2e.exec(
    child,
    [[
    return (function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          vim.api.nvim_set_current_win(win)
          return true
        end
      end
      return false
    end)()
  ]]
  )

  -- Float must still be visible after focusing (BufLeave must NOT close it).
  MiniTest.expect.equality(inspect_win_count(child), 1)

  -- The float-local q keymap closes it.
  e2e.feed(child, "q")
  e2e.wait_until(child, string.format("return (%s) == 0", count_predicate))
end

T["inspect float"]["I: focus stays in the eda buffer after open"] = function()
  cursor_to(child, "sample%.txt")
  e2e.feed(child, "\\i")
  e2e.wait_until(
    child,
    string.format(
      "return (%s) == 1",
      [[(function()
    local n = 0
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].filetype == "eda_inspect" then n = n + 1 end
    end
    return n
  end)()]]
    )
  )

  local current_ft = e2e.exec(child, "return vim.bo[vim.api.nvim_get_current_buf()].filetype")
  MiniTest.expect.no_equality(current_ft, "eda_inspect")
end

T["inspect float"]["H: K triggers debug action (no inspect float opened)"] = function()
  cursor_to(child, "sample%.txt")
  -- K should run the debug action, which calls vim.print but does NOT open the inspect float.
  e2e.feed(child, "K")
  -- Brief sleep to allow any opening to have occurred; then assert count stays at 0.
  e2e.exec(child, "vim.uv.sleep(50)")
  MiniTest.expect.equality(inspect_win_count(child), 0)
end

return T
