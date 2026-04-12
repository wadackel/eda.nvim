local util = require("eda.util")

---@alias eda.WindowTitle string|{[1]: string, [2]: string}[]

---@class eda.Window
---@field winid integer?
---@field bufnr integer?
---@field kind string
---@field config eda.Config
---@field old_winid integer?
---@field header_text eda.WindowTitle?
---@field header_position eda.HeaderPosition?
local Window = {}
Window.__index = Window

local MIN_PREVIEW_WIDTH = 10
local MIN_PREVIEW_HEIGHT = 3
local MIN_FILER_WIDTH = 20

---Resolve a percentage string (e.g. "30%") to an absolute value, or return the number as-is.
---@param val string|number|fun(): number
---@param total number
---@return number
local function resolve_pct(val, total)
  if type(val) == "function" then
    return math.floor(val())
  end
  if type(val) == "string" and val:match("%%$") then
    local pct = tonumber(val:sub(1, -2)) or 30
    return math.floor(total * pct / 100)
  end
  return tonumber(val) or total
end

---Compute layout parameters for a window kind.
---@param kind string
---@param config eda.Config
---@return table
local function compute_layout(kind, config)
  local kind_opts = config.window.kinds[kind] or {}

  if kind == "float" then
    local width = resolve_pct(kind_opts.width or "94%", vim.o.columns)
    local height = resolve_pct(kind_opts.height or "80%", vim.o.lines)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    return {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      border = config.window.border,
      style = "minimal",
      zindex = 50,
    }
  end

  if kind == "split_left" or kind == "split_right" then
    local width = resolve_pct(kind_opts.width or "30%", vim.o.columns)
    return { split = kind == "split_left" and "left" or "right", width = width }
  end

  -- "replace" kind: open in current window
  return { replace = true }
end

---Create a new window manager.
---@param kind string
---@param config eda.Config
---@return eda.Window
function Window.new(kind, config)
  return setmetatable({
    winid = nil,
    bufnr = nil,
    kind = kind,
    config = config,
    old_winid = nil,
    old_bufnr = nil,
  }, Window)
end

---Resolve a stored title value to the form expected by nvim_win_set_config.
---Strings are wrapped with spaces to preserve the historical " Title " padding;
---chunk arrays are passed through unchanged (padding is handled by the caller).
---@param value eda.WindowTitle?
---@return string|table?
local function resolve_title(value)
  if value == nil then
    return nil
  end
  if type(value) == "string" then
    return " " .. value .. " "
  end
  return value
end

---Set the header text for float window title.
---Accepts either a plain string (wrapped with spaces for display) or a chunk
---array (`{{text, hl_group}, ...}`) for titles with per-part highlighting.
---Pass `nil` to clear the title.
---@param text eda.WindowTitle?
function Window:set_header_text(text)
  self.header_text = text
  if self.kind == "float" and self.winid and vim.api.nvim_win_is_valid(self.winid) then
    local resolved = resolve_title(text)
    if resolved ~= nil then
      vim.api.nvim_win_set_config(self.winid, {
        title = resolved,
        title_pos = self.header_position or "left",
      })
    else
      vim.api.nvim_win_set_config(self.winid, { title = "" })
    end
  end
end

---Set the header position for float window title.
---@param position eda.HeaderPosition?
function Window:set_header_position(position)
  self.header_position = position
end

---Open the window and display the given buffer.
---@param bufnr integer
function Window:open(bufnr)
  self.old_winid = vim.api.nvim_get_current_win()
  self.bufnr = bufnr
  local layout = compute_layout(self.kind, self.config)

  -- Add title to float windows when header text is set
  if layout.relative and self.header_text then
    layout.title = resolve_title(self.header_text)
    layout.title_pos = self.header_position or "left"
  end

  if layout.replace then
    self.old_bufnr = vim.api.nvim_get_current_buf()
    self.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_buf(bufnr)
  elseif layout.relative then
    self.winid = vim.api.nvim_open_win(bufnr, true, layout)
  else
    -- Split
    local split_cmd = layout.split == "left" and "topleft vsplit" or "botright vsplit"
    vim.cmd(split_cmd)
    self.winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.winid, bufnr)
    if layout.width then
      vim.api.nvim_win_set_width(self.winid, layout.width)
    end
  end

  -- Apply win_opts
  if util.is_valid_win(self.winid) then
    for k, v in pairs(self.config.window.win_opts) do
      vim.api.nvim_set_option_value(k, v, { win = self.winid })
    end
  end
end

---Reposition the float window after terminal resize.
function Window:reposition()
  if self.kind ~= "float" then
    return
  end
  if not self.winid or not vim.api.nvim_win_is_valid(self.winid) then
    return
  end
  if vim.o.columns < 12 or vim.o.lines < 5 then
    self:close()
    return
  end
  local layout = compute_layout(self.kind, self.config)
  if self.header_text then
    layout.title = resolve_title(self.header_text)
    layout.title_pos = self.header_position or "left"
  end
  vim.api.nvim_win_set_config(self.winid, layout)
end

---Close the window.
function Window:close()
  if self.kind == "replace" then
    -- In replace mode, restore the previous buffer instead of closing the window.
    -- Only restore when the window still shows the eda buffer; if another buffer
    -- is displayed (e.g. after a select action), leave it untouched.
    if util.is_valid_win(self.winid) and self.old_bufnr and vim.api.nvim_buf_is_valid(self.old_bufnr) then
      if self.bufnr and vim.api.nvim_win_get_buf(self.winid) == self.bufnr then
        vim.api.nvim_win_set_buf(self.winid, self.old_bufnr)
      end
    end
  else
    local was_focused = util.is_valid_win(self.winid) and vim.api.nvim_get_current_win() == self.winid
    if util.is_valid_win(self.winid) then
      vim.api.nvim_win_close(self.winid, true)
    end
    if was_focused and util.is_valid_win(self.old_winid) then
      vim.api.nvim_set_current_win(self.old_winid)
    end
  end
  self.winid = nil
  self.old_bufnr = nil
end

---Focus the window.
function Window:focus()
  if util.is_valid_win(self.winid) then
    vim.api.nvim_set_current_win(self.winid)
  end
end

---Check if the window is visible and displaying the eda buffer.
---@return boolean
function Window:is_visible()
  if not util.is_valid_win(self.winid) then
    return false
  end
  if self.bufnr then
    return vim.api.nvim_buf_is_valid(self.bufnr) and vim.api.nvim_win_get_buf(self.winid) == self.bufnr
  end
  return true
end

---Get the window ID for opening files (the window that was active before eda).
---@return integer?
function Window:get_target_winid()
  if util.is_valid_win(self.old_winid) then
    return self.old_winid
  end
  -- Find the first non-eda window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= "eda" and win ~= self.winid then
      return win
    end
  end
  return nil
end

---@class eda.PreviewLayout
---@field preview table
---@field filer? table

---Compute layout parameters for the preview window relative to the filer.
---@param filer_kind string
---@param filer_winid integer
---@param config eda.Config
---@return eda.PreviewLayout?
local function compute_preview_layout(filer_kind, filer_winid, config)
  if filer_kind == "replace" then
    return nil
  end

  if filer_kind == "split_left" or filer_kind == "split_right" then
    local filer_pos = vim.api.nvim_win_get_position(filer_winid)
    local filer_width = vim.api.nvim_win_get_width(filer_winid)
    local filer_height = vim.api.nvim_win_get_height(filer_winid)

    local preview_col, preview_width
    if filer_kind == "split_left" then
      preview_col = filer_pos[2] + filer_width + 1
      preview_width = vim.o.columns - preview_col
    else
      preview_col = 0
      preview_width = filer_pos[2] - 1
    end

    if preview_width < MIN_PREVIEW_WIDTH or filer_height < MIN_PREVIEW_HEIGHT then
      return nil
    end

    return {
      preview = {
        relative = "editor",
        width = preview_width,
        height = filer_height,
        row = filer_pos[1],
        col = preview_col,
        border = config.window.border,
        style = "minimal",
        focusable = false,
        mouse = true,
        zindex = 51,
      },
    }
  end

  if filer_kind == "float" then
    local orig = compute_layout("float", config)
    local filer_width = math.max(math.floor(orig.width * 0.35), MIN_FILER_WIDTH)
    local preview_width = orig.width - filer_width - 2

    if preview_width < MIN_PREVIEW_WIDTH or orig.height < MIN_PREVIEW_HEIGHT then
      return nil
    end

    return {
      preview = {
        relative = "editor",
        width = preview_width,
        height = orig.height,
        row = orig.row,
        col = orig.col + filer_width + 2,
        border = config.window.border,
        style = "minimal",
        focusable = false,
        mouse = true,
        zindex = 51,
      },
      filer = {
        relative = "editor",
        width = filer_width,
        height = orig.height,
        row = orig.row,
        col = orig.col,
      },
    }
  end

  return nil
end

-- Export compute_layout for testing
Window._compute_layout = compute_layout
Window._compute_preview_layout = compute_preview_layout

return Window
