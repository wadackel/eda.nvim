local M = {}

---@type integer?
local _winid = nil
---@type string[]?
local _lines = nil

---Format mapping entries into display lines.
---@param mappings table<string, eda.MappingValue>
---@return string[]
local function format_lines(mappings)
  local entries = {}
  for key, value in pairs(mappings) do
    local action_value, desc
    if type(value) == "table" then
      action_value = value.action
      desc = value.desc
    else
      action_value = value
    end
    if action_value == false then
      goto continue
    end
    local action_name
    if type(action_value) == "function" then
      action_name = "<function>"
    else
      action_name = tostring(action_value)
    end
    local display = desc and (action_name .. " — " .. desc) or action_name
    table.insert(entries, { key = key, action = display })
    ::continue::
  end
  table.sort(entries, function(a, b)
    return a.key < b.key
  end)

  -- Compute max key width for alignment
  local max_key_width = 0
  for _, entry in ipairs(entries) do
    max_key_width = math.max(max_key_width, vim.api.nvim_strwidth(entry.key))
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    local padding = string.rep(" ", max_key_width - vim.api.nvim_strwidth(entry.key))
    table.insert(lines, "  " .. entry.key .. padding .. "   " .. entry.action)
  end
  return lines
end

---Compute the floating window layout for the help dialog.
---@param lines string[]
---@return table
local function compute_help_layout(lines)
  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, vim.api.nvim_strwidth(line))
  end

  local width = math.max(40, max_line_width + 4)
  local height = math.min(#lines, 20)

  local row, col

  local eda = require("eda")
  local current = eda.get_current()
  if current and current.window:is_visible() then
    local win_id = current.window.winid
    ---@diagnostic disable-next-line: param-type-mismatch
    local win_pos = vim.api.nvim_win_get_position(win_id)
    ---@diagnostic disable-next-line: param-type-mismatch
    local win_width = vim.api.nvim_win_get_width(win_id)
    ---@diagnostic disable-next-line: param-type-mismatch
    local win_height = vim.api.nvim_win_get_height(win_id)
    row = win_pos[1] + math.floor((win_height - height) / 2)
    col = win_pos[2] + math.floor((win_width - width) / 2)
  else
    row = math.floor((vim.o.lines - height) / 2)
    col = math.floor((vim.o.columns - width) / 2)
  end

  return {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 52,
    title = " Help ",
    title_pos = "center",
    footer = " q/Esc: close ",
    footer_pos = "center",
  }
end

---Show a help float displaying current keybindings.
---@param mappings table<string, eda.MappingValue>
function M.show(mappings)
  local lines = format_lines(mappings)
  if #lines == 0 then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "eda_help"

  local layout = compute_help_layout(lines)
  local win = vim.api.nvim_open_win(buf, true, layout)
  vim.wo[win].winhl = "FloatBorder:EdaHelpBorder,FloatTitle:EdaHelpTitle,FloatFooter:EdaHelpFooter"

  _winid = win
  _lines = lines

  local function close()
    _winid = nil
    _lines = nil
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, map_opts)
  vim.keymap.set("n", "<Esc>", close, map_opts)
  vim.keymap.set("n", "g?", close, map_opts)
end

---Reposition the help float after terminal resize.
function M.reposition()
  if not _winid or not vim.api.nvim_win_is_valid(_winid) then
    _winid = nil
    _lines = nil
    return
  end
  ---@cast _lines string[]
  local layout = compute_help_layout(_lines)
  if layout.width < 10 or layout.height < 3 then
    local win = _winid
    _winid = nil
    _lines = nil
    vim.api.nvim_win_close(win, true)
    return
  end
  vim.api.nvim_win_set_config(_winid, layout)
end

return M
