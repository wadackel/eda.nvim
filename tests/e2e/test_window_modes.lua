local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["window modes"] = MiniTest.new_set({
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

T["window modes"]["float mode starts and shows filetype eda"] = function()
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

  local lines = e2e.get_buf_lines(child)
  MiniTest.expect.equality(#lines > 0, true)
end

T["window modes"]["float mode closes with q"] = function()
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
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')
end

T["window modes"]["replace mode starts and shows filetype eda"] = function()
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

  -- Replace mode has only 1 window
  MiniTest.expect.equality(e2e.get_win_count(child), 1)
end

T["window modes"]["replace mode closes with q"] = function()
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
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')
end

T["window modes"]["split_right mode starts and shows filetype eda"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_right", width = 40 },
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

  -- split_right creates 2 windows
  MiniTest.expect.equality(e2e.get_win_count(child), 2)
end

T["window modes"]["split_right mode closes with q"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_right", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 1")
end

return T
