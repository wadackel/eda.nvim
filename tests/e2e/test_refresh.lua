local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["refresh"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/existing.txt", "exists")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["refresh"]["reflects externally added file after Ctrl-L"] = function()
  e2e.open_eda(child, tmp)

  -- Verify existing.txt is shown
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return true end
    end
    return false
  ]]
  )

  -- Externally create a new file (from outer Neovim)
  local new_path = tmp .. "/new_file.txt"
  vim.fn.writefile({ "new content" }, new_path)

  -- Press <C-l> to refresh
  e2e.feed(child, "<C-l>")

  -- Wait for new file to appear in the buffer
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("new_file.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["refresh"]["reflects externally deleted file after Ctrl-L"] = function()
  e2e.open_eda(child, tmp)

  -- Verify existing.txt is shown
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return true end
    end
    return false
  ]]
  )

  -- Externally delete the file
  vim.fn.delete(tmp .. "/existing.txt")

  -- Press <C-l> to refresh
  e2e.feed(child, "<C-l>")

  -- Wait for file to disappear from the buffer
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return false end
    end
    return true
  ]],
    10000
  )
end

return T
