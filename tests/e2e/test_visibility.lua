local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["visibility"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/.hidden", "hidden")
      e2e.create_file(tmp .. "/visible.txt", "visible")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["visibility"]["show_hidden=false hides dotfiles"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_hidden = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  local lines = e2e.get_buf_lines(child)

  local has_hidden = false
  local has_visible = false
  for _, line in ipairs(lines) do
    if line:find(".hidden", 1, true) then
      has_hidden = true
    end
    if line:find("visible.txt", 1, true) then
      has_visible = true
    end
  end
  MiniTest.expect.equality(has_hidden, false)
  MiniTest.expect.equality(has_visible, true)
end

T["visibility"]["toggle_hidden toggles dotfile visibility"] = function()
  e2e.setup_eda(child)
  e2e.open_eda(child, tmp)

  -- Default show_hidden=true, dotfile should be visible
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find(".hidden", 1, true) then return true end
    end
    return false
  ]]
  )

  -- Toggle hidden off (g.)
  e2e.feed(child, "g.")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find(".hidden", 1, true) then return false end
    end
    return #lines > 0
  ]]
  )

  -- Toggle hidden on again (g.)
  e2e.feed(child, "g.")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find(".hidden", 1, true) then return true end
    end
    return false
  ]]
  )
end

T["visibility"]["ignore_patterns hides matching files"] = function()
  -- Create additional files for this test
  e2e.create_file(tmp .. "/app.log", "log")
  e2e.create_file(tmp .. "/temp_cache", "cache")
  e2e.create_file(tmp .. "/keep.txt", "keep")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      ignore_patterns = { "%.log$", "^temp_" },
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  local lines = e2e.get_buf_lines(child)

  local has_log = false
  local has_temp = false
  local has_keep = false
  for _, line in ipairs(lines) do
    if line:find("app.log", 1, true) then
      has_log = true
    end
    if line:find("temp_cache", 1, true) then
      has_temp = true
    end
    if line:find("keep.txt", 1, true) then
      has_keep = true
    end
  end
  MiniTest.expect.equality(has_log, false)
  MiniTest.expect.equality(has_temp, false)
  MiniTest.expect.equality(has_keep, true)
end

return T
