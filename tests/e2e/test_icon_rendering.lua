local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["icon_rendering"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/alpha_dir")
      e2e.create_file(tmp .. "/beta_file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["icon_rendering"]["directory icons are rendered on screen"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for icon extmarks to be created in ns_icon
  e2e.wait_until(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(0, painter.ns_icon, 0, -1, {})
    return #marks > 0
  ]],
    5000
  )

  -- Verify directory line has an icon on screen (non-ASCII first character)
  local result = e2e.exec(
    child,
    [[
    vim.cmd("redraw!")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local dir_row = nil
    for i, line in ipairs(lines) do
      if line:find("alpha_dir/") then
        dir_row = i
        break
      end
    end
    if not dir_row then
      return { found = false }
    end

    local first_char = vim.fn.screenstring(dir_row, 1)
    local byte = string.byte(first_char, 1) or 0
    return {
      found = true,
      first_char_byte = byte,
      is_icon = byte > 127,
    }
  ]]
  )

  MiniTest.expect.equality(result.found, true)
  MiniTest.expect.equality(result.is_icon, true)
end

T["icon_rendering"]["file icons are not rendered when provider is none"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for render to complete
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("beta_file") then return true end
    end
    return false
  ]],
    5000
  )

  -- File line should NOT have an icon (first screen char = first char of filename)
  local result = e2e.exec(
    child,
    [[
    vim.cmd("redraw!")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local file_row = nil
    for i, line in ipairs(lines) do
      if line:find("beta_file") then
        file_row = i
        break
      end
    end
    if not file_row then
      return { found = false }
    end

    local first_char = vim.fn.screenstring(file_row, 1)
    return {
      found = true,
      first_char = first_char,
    }
  ]]
  )

  MiniTest.expect.equality(result.found, true)
  MiniTest.expect.equality(result.first_char, "b")
end

T["icon_rendering"]["custom overrides file icon"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = {
        provider = "none",
        custom = function(name, _node)
          if name == "beta_file.txt" then
            return "!", "EdaFileIcon"
          end
          return nil
        end,
      },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, line in ipairs(lines) do
      if line:find("beta_file") then return true end
    end
    return false
  ]],
    5000
  )

  local result = e2e.exec(
    child,
    [[
    vim.cmd("redraw!")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local file_row = nil
    local dir_row = nil
    for i, line in ipairs(lines) do
      if line:find("beta_file") then file_row = i end
      if line:find("alpha_dir") then dir_row = i end
    end
    if not file_row or not dir_row then
      return { found = false }
    end
    return {
      found = true,
      file_first_char = vim.fn.screenstring(file_row, 1),
      dir_first_char = vim.fn.screenstring(dir_row, 1),
    }
  ]]
  )

  MiniTest.expect.equality(result.found, true)
  -- Custom returned "!" for beta_file.txt
  MiniTest.expect.equality(result.file_first_char, "!")
  -- Directory unaffected: custom returned nil, so directory.collapsed glyph should appear.
  -- With provider=none the directory still uses the built-in nested directory glyph,
  -- which is a Nerd Font character (byte > 127) rather than the literal "a" of "alpha_dir".
  local byte = string.byte(result.dir_first_char, 1) or 0
  MiniTest.expect.equality(byte > 127, true)
end

T["icon_rendering"]["icon extmarks resync after dd"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for icon extmarks to be created in ns_icon
  e2e.wait_until(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(0, painter.ns_icon, 0, -1, {})
    return #marks > 0
  ]],
    5000
  )

  -- Record initial icon extmark count
  local before = e2e.exec(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(0, painter.ns_icon, 0, -1, {})
    return { count = #marks }
  ]]
  )

  -- Move cursor to first line and delete it with dd
  e2e.feed(child, "ggdd")

  -- Wait for TextChanged to fire and resync (icon count should decrease)
  e2e.wait_until(child, [[
    local painter = require("eda").get_current().buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(0, painter.ns_icon, 0, -1, {})
    return #marks < ]] .. before.count .. [[

  ]], 5000)

  -- Verify remaining icon extmarks are at correct row positions
  local after = e2e.exec(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(0, painter.ns_icon, 0, -1, {})
    local rows = {}
    for _, m in ipairs(marks) do
      table.insert(rows, m[2])
    end
    local flat_count = #painter._flat_lines
    local buf_lines = vim.api.nvim_buf_line_count(0)
    return { count = #marks, rows = rows, flat_count = flat_count, buf_lines = buf_lines }
  ]]
  )

  -- After deleting one line, flat_lines should match buffer line count
  MiniTest.expect.equality(after.flat_count, after.buf_lines)

  -- Icon extmark rows should be sequential (no gaps or displaced marks)
  for i, row in ipairs(after.rows) do
    MiniTest.expect.equality(row, i - 1)
  end
end

return T
