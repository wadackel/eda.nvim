local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["header"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "content")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["header"]["format=full shows absolute path in split mode"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = { format = "full", divider = false },
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  local lines = e2e.get_buf_lines(child)

  -- First line should be the absolute path of the temp directory
  MiniTest.expect.equality(lines[1], tmp)
  -- Second line should be a file entry (not another header)
  MiniTest.expect.equality(lines[2]:find("file.txt", 1, true) ~= nil, true)
end

T["header"]["divider=true shows separator line below header"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = { format = "short", divider = true },
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  local lines = e2e.get_buf_lines(child)

  -- Line 1: header text (non-empty path)
  MiniTest.expect.equality(#lines[1] > 0, true)

  -- Line 2: divider (horizontal box-drawing characters)
  local divider_char = string.char(0xe2, 0x94, 0x80)
  MiniTest.expect.equality(lines[2]:find(divider_char, 1, true) ~= nil, true)

  -- Line 3: file entry
  MiniTest.expect.equality(lines[3]:find("file.txt", 1, true) ~= nil, true)
end

T["header"]["position=center sets float window title_pos"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = { format = "short", position = "center" },
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  local title_pos = e2e.exec(child, "return vim.api.nvim_win_get_config(0).title_pos")
  MiniTest.expect.equality(title_pos, "center")
end

return T
