local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["open and select"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/src")
      e2e.create_file(tmp .. "/src/main.lua", "-- main")
      e2e.create_file(tmp .. "/README.md", "# readme")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["open and select"]["displays files and directories in buffer"] = function()
  e2e.open_eda(child, tmp)
  local lines = e2e.get_buf_lines(child)

  -- Directories come first (natural sort), then files
  local has_src = false
  local has_readme = false
  for _, line in ipairs(lines) do
    if line:find("src/") then
      has_src = true
    end
    if line:find("README.md") then
      has_readme = true
    end
  end
  MiniTest.expect.equality(has_src, true)
  MiniTest.expect.equality(has_readme, true)
end

T["open and select"]["expands and collapses directory with CR"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to src/ line (first line, directories come first)
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")

  -- Expand with <CR>
  e2e.feed(child, "<CR>")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("main.lua") then return true end
    end
    return false
  ]]
  )

  -- Collapse with <CR>
  e2e.feed(child, "<CR>")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("main.lua") then return false end
    end
    return true
  ]]
  )
end

T["open and select"]["opens file in target window with CR"] = function()
  e2e.open_eda(child, tmp)

  -- Move cursor to README.md line (second line, after src/)
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {2, 0})")

  -- Select file with <CR>
  e2e.feed(child, "<CR>")
  e2e.wait_until(
    child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "README.md")
  )
end

T["open and select"]["closes explorer with q"] = function()
  e2e.open_eda(child, tmp)

  -- Focus the eda window
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 1")
end

-- close_on_select tests
local cos_child, cos_tmp

T["close_on_select"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      cos_child = e2e.spawn()
      cos_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(cos_tmp .. "/alpha.txt", "alpha")
    end,
    post_case = function()
      e2e.stop(cos_child)
      e2e.remove_temp_dir(cos_tmp)
    end,
  },
})

T["close_on_select"]["close_on_select=true closes eda after file select"] = function()
  e2e.exec(
    cos_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      close_on_select = true,
    })
  ]]
  )

  e2e.open_eda(cos_child, cos_tmp)

  -- Move cursor to the file line and select
  e2e.exec(cos_child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(cos_child, "<CR>")

  -- Eda window should close, leaving only the file window
  e2e.wait_until(cos_child, "#vim.api.nvim_list_wins() == 1")
  e2e.wait_until(cos_child, 'vim.bo.filetype ~= "eda"')
end

T["close_on_select"]["close_on_select=false keeps eda open after file select"] = function()
  e2e.exec(
    cos_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      close_on_select = false,
    })
  ]]
  )

  e2e.open_eda(cos_child, cos_tmp)

  -- Move cursor to the file line and select
  e2e.exec(cos_child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(cos_child, "<CR>")

  -- File should open but eda window should remain
  e2e.wait_until(
    cos_child,
    string.format([[vim.fn.bufname(vim.api.nvim_get_current_buf()):find(%q, 1, true) ~= nil]], "alpha.txt")
  )
  MiniTest.expect.equality(e2e.get_win_count(cos_child) >= 2, true)

  -- Verify eda window still exists
  e2e.wait_until(
    cos_child,
    [[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "eda" then return true end
    end
    return false
  ]]
  )
end

return T
