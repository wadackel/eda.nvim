local config = require("eda.config")

local M = {}

---@type integer?
local _winid = nil
---@type string[]?
local _lines = nil
---@type table[]?
local _title_chunks = nil
---@type fun()?
local _on_cancel = nil

---Format a path according to the path_format setting.
---@param path string Absolute path
---@param root_path string Root directory path
---@param fmt eda.ConfirmPathFormat
---@return string
local function format_path(path, root_path, fmt)
  if type(fmt) == "function" then
    return fmt(path, root_path)
  end
  if fmt == "full" then
    return path
  end
  -- Strip root_path prefix to get relative path
  local rel = path
  if path:sub(1, #root_path + 1) == root_path .. "/" then
    rel = path:sub(#root_path + 2)
  end
  if fmt == "minimal" then
    local parts = vim.split(rel, "/", { plain = true })
    if #parts > 1 then
      for i = 1, #parts - 1 do
        parts[i] = vim.fn.strcharpart(parts[i], 0, 1)
      end
    end
    return table.concat(parts, "/")
  end
  -- "short" (default)
  return rel
end

---Abbreviate MOVE destination by replacing common directory prefix with "...".
---@param src_display string Formatted source path
---@param dst_display string Formatted destination path
---@return string Abbreviated destination
local function abbreviate_dst(src_display, dst_display)
  local src_parts = vim.split(src_display, "/", { plain = true })
  local dst_parts = vim.split(dst_display, "/", { plain = true })
  local common = 0
  for i = 1, math.min(#src_parts - 1, #dst_parts - 1) do
    if src_parts[i] == dst_parts[i] then
      common = i
    else
      break
    end
  end
  if common == 0 then
    return dst_display
  end
  return ".../" .. table.concat(dst_parts, "/", common + 1)
end

---@class eda.ConfirmSegment
---@field line integer 0-indexed line number
---@field sign_hl string Highlight group for the sign (+/-/~)
---@field sign_col integer[] {start, end_} byte columns
---@field path_hl string Highlight group for the path
---@field path_col integer[] {start, end_} byte columns

---@class eda.ConfirmFormatResult
---@field lines string[]
---@field segments eda.ConfirmSegment[]
---@field counts { delete: integer, create: integer, move: integer }

---Format operations for display in the confirm buffer.
---@param operations eda.Operation[]
---@param root_path string
---@param path_format eda.ConfirmPathFormat
---@param signs eda.ConfirmSigns
---@return eda.ConfirmFormatResult
local function format_operations(operations, root_path, path_format, signs)
  local lines = { "" }
  local segments = {}
  local counts = { delete = 0, create = 0, move = 0 }
  for _, op in ipairs(operations) do
    if op.type == "create" then
      counts.create = counts.create + 1
      local kind = op.entry_type == "directory" and "dir" or "file"
      local path = format_path(op.path, root_path, path_format)
      local sign = signs.create
      local suffix = "  (" .. kind .. ")"
      local line = "  " .. sign .. "  " .. path .. suffix
      local line_idx = #lines
      table.insert(lines, line)
      local sign_start = 2
      local sign_end = sign_start + #sign
      local path_start = sign_end + 2
      local path_end = path_start + #path
      table.insert(segments, {
        line = line_idx,
        sign_hl = "EdaOpCreateSign",
        sign_col = { sign_start, sign_end },
        path_hl = "EdaOpCreatePath",
        path_col = { path_start, path_end },
      })
    elseif op.type == "delete" then
      counts.delete = counts.delete + 1
      local path = format_path(op.path, root_path, path_format)
      local sign = signs.delete
      local line = "  " .. sign .. "  " .. path
      local line_idx = #lines
      table.insert(lines, line)
      local sign_start = 2
      local sign_end = sign_start + #sign
      local path_start = sign_end + 2
      local path_end = path_start + #path
      table.insert(segments, {
        line = line_idx,
        sign_hl = "EdaOpDeleteSign",
        sign_col = { sign_start, sign_end },
        path_hl = "EdaOpDeletePath",
        path_col = { path_start, path_end },
      })
    elseif op.type == "move" then
      counts.move = counts.move + 1
      local src = format_path(op.src, root_path, path_format)
      local dst = format_path(op.dst, root_path, path_format)
      dst = abbreviate_dst(src, dst)
      local arrow = " → "
      local sign = signs.move
      local line = "  " .. sign .. "  " .. src .. arrow .. dst
      local line_idx = #lines
      table.insert(lines, line)
      local sign_start = 2
      local sign_end = sign_start + #sign
      local path_start = sign_end + 2
      local path_end = path_start + #src + #arrow + #dst
      table.insert(segments, {
        line = line_idx,
        sign_hl = "EdaOpMoveSign",
        sign_col = { sign_start, sign_end },
        path_hl = "EdaOpMovePath",
        path_col = { path_start, path_end },
      })
    end
  end

  table.insert(lines, "")
  return { lines = lines, segments = segments, counts = counts }
end

---Build title chunks for the confirm dialog window title.
---@param counts { delete: integer, create: integer, move: integer }
---@param signs eda.ConfirmSigns
---@return table[] Array of {text, hl_group} chunks for nvim_open_win title
local function build_title_chunks(counts, signs)
  local chunks = { { " Confirm: ", "EdaConfirmTitle" } }
  local entries = {
    { count = counts.delete, sign = signs.delete, hl = "EdaOpDeleteSign", text_hl = "EdaOpDeleteText" },
    { count = counts.create, sign = signs.create, hl = "EdaOpCreateSign", text_hl = "EdaOpCreateText" },
    { count = counts.move, sign = signs.move, hl = "EdaOpMoveSign", text_hl = "EdaOpMoveText" },
  }
  local added = false
  for _, entry in ipairs(entries) do
    if entry.count > 0 then
      if added then
        table.insert(chunks, { " ", "EdaConfirmTitle" })
      end
      table.insert(chunks, { entry.sign, entry.hl })
      table.insert(chunks, { " " .. entry.count, entry.text_hl })
      added = true
    end
  end
  table.insert(chunks, { " ", "EdaConfirmTitle" })
  return chunks
end

---Compute the floating window layout for the confirm dialog.
---@param lines string[]
---@param title_chunks table[] Array of {text, hl_group} chunks
---@return table
local function compute_confirm_layout(lines, title_chunks)
  local max_line_width = 0
  for _, line in ipairs(lines) do
    max_line_width = math.max(max_line_width, vim.api.nvim_strwidth(line))
  end

  -- Compute title display width
  local title_width = 0
  for _, chunk in ipairs(title_chunks) do
    title_width = title_width + vim.api.nvim_strwidth(chunk[1])
  end

  local width = math.max(40, max_line_width + 4, title_width + 4)
  local height = math.min(#lines, 15)

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
    title = title_chunks,
    title_pos = "center",
    footer = " y/Enter: confirm  q/Esc: cancel ",
    footer_pos = "center",
  }
end

---Show a confirmation float for operations.
---@param operations eda.Operation[]
---@param root_path string
---@param on_confirm fun() Called when user confirms
---@param on_cancel fun() Called when user cancels
function M.show(operations, root_path, on_confirm, on_cancel)
  if #operations == 0 then
    on_confirm()
    return
  end

  local cfg = config.get()
  local path_format = cfg.confirm and cfg.confirm.path_format or "short"
  local signs = cfg.confirm and cfg.confirm.signs or { create = "+", delete = "-", move = "~" }
  local result = format_operations(operations, root_path, path_format, signs)
  local lines = result.lines

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "eda_confirm"

  -- Apply highlights
  local ns = vim.api.nvim_create_namespace("eda_confirm_hl")
  for _, seg in ipairs(result.segments) do
    vim.api.nvim_buf_set_extmark(buf, ns, seg.line, seg.sign_col[1], {
      end_col = seg.sign_col[2],
      hl_group = seg.sign_hl,
    })
    vim.api.nvim_buf_set_extmark(buf, ns, seg.line, seg.path_col[1], {
      end_col = seg.path_col[2],
      hl_group = seg.path_hl,
    })
  end

  -- Open float window
  local title_chunks = build_title_chunks(result.counts, signs)
  local layout = compute_confirm_layout(lines, title_chunks)
  local win = vim.api.nvim_open_win(buf, true, layout)
  vim.wo[win].winhl = "FloatBorder:EdaConfirmBorder,FloatTitle:EdaConfirmTitle,FloatFooter:EdaConfirmFooter"

  _winid = win
  _lines = lines
  _title_chunks = title_chunks
  _on_cancel = on_cancel

  local function close_and_do(fn)
    _winid = nil
    _lines = nil
    _title_chunks = nil
    _on_cancel = nil
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    fn()
  end

  -- Keymaps
  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "y", function()
    close_and_do(on_confirm)
  end, map_opts)
  vim.keymap.set("n", "<CR>", function()
    close_and_do(on_confirm)
  end, map_opts)
  vim.keymap.set("n", "q", function()
    close_and_do(on_cancel)
  end, map_opts)
  vim.keymap.set("n", "<Esc>", function()
    close_and_do(on_cancel)
  end, map_opts)
end

---Reposition the confirm float after terminal resize.
function M.reposition()
  if not _winid or not vim.api.nvim_win_is_valid(_winid) then
    _winid = nil
    _lines = nil
    _title_chunks = nil
    _on_cancel = nil
    return
  end
  ---@cast _lines string[]
  ---@cast _title_chunks table[]
  local layout = compute_confirm_layout(_lines, _title_chunks)
  if layout.width < 10 or layout.height < 3 then
    local win = _winid
    local cancel = _on_cancel
    _winid = nil
    _lines = nil
    _title_chunks = nil
    _on_cancel = nil
    vim.api.nvim_win_close(win, true)
    if cancel then
      cancel()
    end
    return
  end
  vim.api.nvim_win_set_config(_winid, layout)
end

-- Export for testing
M._compute_confirm_layout = compute_confirm_layout
M._build_title_chunks = build_title_chunks
M._format_operations = format_operations
M._format_path = format_path
M._abbreviate_dst = abbreviate_dst

return M
