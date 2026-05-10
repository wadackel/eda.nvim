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

T["window modes"]["float mode reopens in replace mode with bang"] = function()
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
  e2e.wait_until(child, 'vim.bo.filetype == "eda" and #vim.api.nvim_list_wins() == 2')

  e2e.feed(child, "!")
  e2e.wait_until(
    child,
    [[
    local has_file = false
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("file.txt", 1, true) then
        has_file = true
        break
      end
    end
    return vim.bo.filetype == "eda"
      and #vim.api.nvim_list_wins() == 1
      and require("eda").get_current().window.kind == "replace"
      and require("eda").get_current().is_split == false
      and #require("eda").get_all() == 1
      and has_file
  ]]
  )
end

T["window modes"]["open_replace refuses modified float buffer"] = function()
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
  e2e.wait_until(child, 'vim.bo.filetype == "eda" and #vim.api.nvim_list_wins() == 2')

  local result = e2e.exec(
    child,
    [[
    local eda = require("eda")
    local explorer = eda.get_current()
    vim.bo[explorer.buffer.bufnr].modified = true
    require("eda.action").dispatch("open_replace", {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = require("eda.config").get(),
      explorer = explorer,
    })
    return {
      kind = eda.get_current().window.kind,
      instances = #eda.get_all(),
      windows = #vim.api.nvim_list_wins(),
      modified = vim.bo[explorer.buffer.bufnr].modified,
    }
  ]]
  )

  MiniTest.expect.equality(result.kind, "float")
  MiniTest.expect.equality(result.instances, 1)
  MiniTest.expect.equality(result.windows, 2)
  MiniTest.expect.equality(result.modified, true)
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
