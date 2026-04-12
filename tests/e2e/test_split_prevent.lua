local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["split prevention"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["split prevention"]["closes split window on eda buffer"] = function()
  e2e.open_eda(child, tmp)

  -- Record initial window count (should be 2: eda split + target)
  local win_count_before = e2e.exec(child, "return #vim.api.nvim_list_wins()")
  MiniTest.expect.equality(win_count_before, 2)

  -- Execute :vsplit on the eda buffer
  -- In headless --listen mode, BufWinEnter does not fire automatically,
  -- so we manually trigger it with doautocmd.
  e2e.exec(child, 'vim.cmd("vsplit")')
  e2e.exec(child, 'vim.cmd("doautocmd BufWinEnter")')

  -- Wait for the split to be closed by the autocmd
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 2")

  -- Verify eda buffer is still functional (filetype preserved)
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')
end

T["replace mode"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["replace mode"]["opens without split detect error"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))

  -- Wait for eda buffer to be ready
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- Verify buffer has content (scan completed)
  local lines = e2e.get_buf_lines(child)
  MiniTest.expect.equality(#lines > 0, true)
end

T["replace mode"]["detects split after startup"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))

  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- In replace mode there is only 1 window
  local win_count_before = e2e.exec(child, "return #vim.api.nvim_list_wins()")
  MiniTest.expect.equality(win_count_before, 1)

  -- Execute :vsplit + manually trigger BufWinEnter (suppressed in headless mode)
  e2e.exec(child, 'vim.cmd("vsplit")')
  e2e.exec(child, 'vim.cmd("doautocmd BufWinEnter")')

  -- Wait for the split to be closed by the autocmd
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 1")
end

T["float mode"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["float mode"]["opens without split detect error"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))

  -- Wait for eda buffer to be ready
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- Verify buffer has content (scan completed)
  local lines = e2e.get_buf_lines(child)
  MiniTest.expect.equality(#lines > 0, true)
end

T["float mode"]["detects split after startup"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))

  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- In float mode there are 2 windows (original + float)
  local win_count_before = e2e.exec(child, "return #vim.api.nvim_list_wins()")
  MiniTest.expect.equality(win_count_before, 2)

  -- Execute :vsplit + manually trigger BufWinEnter (suppressed in headless mode)
  e2e.exec(child, 'vim.cmd("vsplit")')
  e2e.exec(child, 'vim.cmd("doautocmd BufWinEnter")')

  -- Wait for the split to be closed by the autocmd
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 2")
end

return T
