local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["file select"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/alpha.txt", "alpha")
      e2e.create_file(tmp .. "/beta.txt", "beta")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["file select"]["select_vsplit opens file in vertical split"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press | for select_vsplit
  e2e.feed(child, "|")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )

  -- Should have 3 windows: eda + original target + new vsplit
  MiniTest.expect.equality(e2e.get_win_count(child), 3)
end

T["file select"]["select_split opens file in horizontal split"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press - for select_split
  e2e.feed(child, "-")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )

  -- Should have 3 windows: eda + original target + new split
  MiniTest.expect.equality(e2e.get_win_count(child), 3)
end

T["file select"]["select_tab opens file in new tab"] = function()
  e2e.open_eda(child, tmp)

  local tabs_before = e2e.get_tab_count(child)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press <C-t> for select_tab
  e2e.feed(child, "<C-t>")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )

  -- Should have one more tab
  local tabs_after = e2e.get_tab_count(child)
  MiniTest.expect.equality(tabs_after, tabs_before + 1)
end

T["file select float"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.exec(
        child,
        [[
        require("eda").setup({
          git = { enabled = false },
          icon = { provider = "none" },
          confirm = false,
          header = false,
          window = { kind = "float" },
        })
      ]]
      )
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/alpha.txt", "alpha")
      e2e.create_file(tmp .. "/beta.txt", "beta")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["file select float"]["select_vsplit in float mode focuses the new split"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press | for select_vsplit
  e2e.feed(child, "|")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )

  -- Float should be closed; 2 windows remain (original + new vsplit)
  MiniTest.expect.equality(e2e.get_win_count(child), 2)
end

T["file select float"]["select_split in float mode focuses the new split"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Press - for select_split
  e2e.feed(child, "-")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )

  -- Float should be closed; 2 windows remain (original + new split)
  MiniTest.expect.equality(e2e.get_win_count(child), 2)
end

return T
