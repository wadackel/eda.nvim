local util = require("eda.util")

---@class eda.FullName
---@field winid integer?
---@field bufnr integer
---@field config eda.FullNameConfig
---@field _ns integer
local FullName = {}
FullName.__index = FullName

---Create a new full-name popup manager.
---@param config eda.FullNameConfig
---@return eda.FullName
function FullName.new(config)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"

  return setmetatable({
    winid = nil,
    bufnr = bufnr,
    config = config,
    _ns = vim.api.nvim_create_namespace(""),
  }, FullName)
end

---Compute the total display width of a line including virtual text.
---@param flat_line eda.FlatLine
---@param entry { icon_text: string?, icon_hl: string, name_hl: string|string[], suffix: string?, suffix_hl: string, link_suffix: string?, link_suffix_hl: string? }
---@param indent_width integer
---@return integer
function FullName.compute_display_width(flat_line, entry, indent_width)
  local node = flat_line.node
  local name = node.name
  if node.type == "directory" then
    name = name .. "/"
  end

  local total = flat_line.depth * indent_width
  total = total + (entry.icon_text and vim.api.nvim_strwidth(entry.icon_text) or 0)
  total = total + vim.api.nvim_strwidth(name)
  if entry.link_suffix then
    total = total + vim.api.nvim_strwidth(entry.link_suffix)
  end
  if entry.suffix then
    total = total + vim.api.nvim_strwidth(entry.suffix)
  end
  return total
end

---Update the popup for the current cursor position.
---@param eda_winid integer
---@param painter eda.Painter
---@param flat_lines eda.FlatLine[]
function FullName:update(eda_winid, painter, flat_lines)
  if not self.config.enabled then
    return
  end

  self:close()

  if not util.is_valid_win(eda_winid) then
    return
  end
  if vim.wo[eda_winid].wrap then
    return
  end
  local view = vim.fn.winsaveview()
  if view.leftcol ~= 0 then
    return
  end

  local cursor_row = vim.api.nvim_win_get_cursor(eda_winid)[1]
  local fl_index = painter._row_to_fl[cursor_row - 1]
  if not fl_index then
    return
  end
  local fl = flat_lines[fl_index]
  if not fl then
    return
  end
  local entry = painter._decoration_cache[fl.node_id]
  if not entry then
    return
  end

  local total_width = FullName.compute_display_width(fl, entry, painter.indent_width)

  local win_info = vim.fn.getwininfo(eda_winid)
  if not win_info or #win_info == 0 then
    return
  end
  local textoff = win_info[1].textoff
  local win_width = vim.api.nvim_win_get_width(eda_winid)
  local effective_width = win_width - textoff
  if total_width <= effective_width then
    return
  end

  -- Build popup buffer content
  local indent_len = fl.depth * painter.indent_width
  local node = fl.node
  local name = node.name
  if node.type == "directory" then
    name = name .. "/"
  end
  local line_text = string.rep(" ", indent_len) .. name
  local line_len = #line_text

  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, { line_text })
  vim.api.nvim_buf_clear_namespace(self.bufnr, self._ns, 0, -1)

  -- Icon (inline virtual text)
  if entry.icon_text then
    vim.api.nvim_buf_set_extmark(self.bufnr, self._ns, 0, indent_len, {
      virt_text = { { entry.icon_text, entry.icon_hl } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end

  -- Name highlight
  if indent_len < line_len then
    vim.api.nvim_buf_set_extmark(self.bufnr, self._ns, 0, indent_len, {
      end_col = line_len,
      hl_group = entry.name_hl,
      hl_mode = "combine",
    })
  end

  -- Link suffix (symlink target, rendered first at EOL)
  if entry.link_suffix then
    vim.api.nvim_buf_set_extmark(self.bufnr, self._ns, 0, 0, {
      virt_text = { { entry.link_suffix, entry.link_suffix_hl } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end

  -- Suffix (git status, rendered after link suffix)
  if entry.suffix then
    vim.api.nvim_buf_set_extmark(self.bufnr, self._ns, 0, 0, {
      virt_text = { { entry.suffix, entry.suffix_hl } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
  end

  -- Open floating window
  local popup_width = math.max(total_width, win_width)
  local row = cursor_row - vim.fn.line("w0", eda_winid)

  self.winid = vim.api.nvim_open_win(self.bufnr, false, {
    relative = "win",
    win = eda_winid,
    row = row,
    col = 0,
    width = popup_width,
    height = 1,
    border = "none",
    style = "minimal",
    focusable = false,
    zindex = 51,
    noautocmd = true,
  })

  vim.wo[self.winid].winhighlight = "Normal:EdaFullNameNormal,CursorLine:EdaFullNameNormal"
  vim.wo[self.winid].cursorline = false
end

---Close the popup window (buffer is preserved for reuse).
function FullName:close()
  if util.is_valid_win(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end
  self.winid = nil
end

---Destroy the popup, including the buffer.
function FullName:destroy()
  self:close()
  if util.is_valid_buf(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

return FullName
