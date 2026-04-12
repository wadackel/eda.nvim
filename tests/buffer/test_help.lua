local Help = require("eda.buffer.help")

local T = MiniTest.new_set()

---Helper to find the help float window.
---@return integer? win_id
---@return integer? buf_id
local function find_help_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_help" then
      return win, buf
    end
  end
  return nil, nil
end

T["show creates float window with correct filetype and readonly"] = function()
  local mappings = {
    ["<CR>"] = "select",
    ["q"] = "close",
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.no_equality(buf, nil)

  MiniTest.expect.equality(vim.bo[buf].filetype, "eda_help")
  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show excludes false mappings"] = function()
  local mappings = {
    ["<CR>"] = "select",
    ["q"] = false,
    ["x"] = "close",
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 2)

  -- Verify "q" (disabled) is not present
  local has_q = false
  for _, line in ipairs(lines) do
    if line:find("close") and line:find("q") then
      has_q = true
    end
  end
  MiniTest.expect.equality(has_q, false)

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show displays function values as <function>"] = function()
  local mappings = {
    ["a"] = function() end,
    ["b"] = "select",
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 2)

  -- First line should be "a" with <function> (sorted alphabetically)
  MiniTest.expect.equality(lines[1]:find("<function>") ~= nil, true)
  MiniTest.expect.equality(lines[2]:find("select") ~= nil, true)

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show sorts entries alphabetically by key"] = function()
  local mappings = {
    ["z"] = "action_z",
    ["a"] = "action_a",
    ["m"] = "action_m",
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)
  MiniTest.expect.equality(lines[1]:find("action_a") ~= nil, true)
  MiniTest.expect.equality(lines[2]:find("action_m") ~= nil, true)
  MiniTest.expect.equality(lines[3]:find("action_z") ~= nil, true)

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show does nothing with empty mappings"] = function()
  Help.show({})

  local win, _ = find_help_window()
  MiniTest.expect.equality(win, nil)
end

T["show does nothing when all mappings are false"] = function()
  Help.show({ ["q"] = false, ["<CR>"] = false })

  local win, _ = find_help_window()
  MiniTest.expect.equality(win, nil)
end

T["q keymap closes the help window"] = function()
  Help.show({ ["<CR>"] = "select" })

  local win, _ = find_help_window()
  MiniTest.expect.no_equality(win, nil)

  vim.api.nvim_feedkeys("q", "x", false)

  local win_after, _ = find_help_window()
  MiniTest.expect.equality(win_after, nil)
end

T["Esc keymap closes the help window"] = function()
  Help.show({ ["<CR>"] = "select" })

  local win, _ = find_help_window()
  MiniTest.expect.no_equality(win, nil)

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local win_after, _ = find_help_window()
  MiniTest.expect.equality(win_after, nil)
end

T["g? keymap closes the help window"] = function()
  Help.show({ ["<CR>"] = "select" })

  local win, _ = find_help_window()
  MiniTest.expect.no_equality(win, nil)

  vim.api.nvim_feedkeys("g?", "x", false)

  local win_after, _ = find_help_window()
  MiniTest.expect.equality(win_after, nil)
end

T["show sets window highlights"] = function()
  Help.show({ ["<CR>"] = "select" })

  local win, _ = find_help_window()
  MiniTest.expect.no_equality(win, nil)

  local winhl = vim.wo[win].winhl
  MiniTest.expect.equality(winhl:find("FloatBorder:EdaHelpBorder") ~= nil, true)
  MiniTest.expect.equality(winhl:find("FloatTitle:EdaHelpTitle") ~= nil, true)
  MiniTest.expect.equality(winhl:find("FloatFooter:EdaHelpFooter") ~= nil, true)

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show sets correct float config"] = function()
  Help.show({ ["<CR>"] = "select" })

  local win, _ = find_help_window()
  MiniTest.expect.no_equality(win, nil)

  local win_config = vim.api.nvim_win_get_config(win)
  MiniTest.expect.equality(win_config.zindex, 52)
  MiniTest.expect.equality(win_config.relative, "editor")

  -- Clean up
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show displays table-form mapping with action name"] = function()
  local mappings = {
    ["a"] = { action = "select" },
    ["b"] = "close",
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 2)
  MiniTest.expect.equality(lines[1]:find("select") ~= nil, true)
  MiniTest.expect.equality(lines[2]:find("close") ~= nil, true)

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show displays table-form mapping with desc"] = function()
  local mappings = {
    ["a"] = { action = "select", desc = "Open file" },
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1]:find("select") ~= nil, true)
  MiniTest.expect.equality(lines[1]:find("Open file") ~= nil, true)

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show displays table-form function mapping as <function>"] = function()
  local mappings = {
    ["a"] = { action = function() end, desc = "Custom action" },
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1]:find("<function>") ~= nil, true)
  MiniTest.expect.equality(lines[1]:find("Custom action") ~= nil, true)

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

T["show excludes table-form false mapping"] = function()
  local mappings = {
    ["a"] = "select",
    ["b"] = { action = false },
  }

  Help.show(mappings)

  local win, buf = find_help_window()
  MiniTest.expect.no_equality(buf, nil)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1]:find("select") ~= nil, true)

  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end
return T
