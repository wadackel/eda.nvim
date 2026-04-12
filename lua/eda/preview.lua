local util = require("eda.util")

---@class eda.Preview
---@field winid integer?
---@field bufnr integer?
---@field config eda.PreviewConfig
---@field window eda.Window?
---@field _debounced fun(path: string)?
---@field _pending_path string?
---@field _current_path string?
local Preview = {}
Preview.__index = Preview

---Create a new preview manager.
---@param config eda.PreviewConfig
---@return eda.Preview
function Preview.new(config)
  return setmetatable({
    winid = nil,
    bufnr = nil,
    config = config,
    window = nil,
    _debounced = nil,
    _pending_path = nil,
    _current_path = nil,
  }, Preview)
end

---Attach the filer window to this preview for layout computation.
---@param window eda.Window
function Preview:attach(window)
  self.window = window
end

---Check if a file is binary (contains NUL byte in first 512 bytes).
---@param path string
---@return boolean
local function is_binary(path)
  local f = io.open(path, "rb")
  if not f then
    return false
  end
  local data = f:read(512)
  f:close()
  if not data then
    return false
  end
  return data:find("\0") ~= nil
end

---Show preview for a file.
---@param path string
function Preview:show(path)
  if not self.config.enabled then
    return
  end

  if not self.window or not util.is_valid_win(self.window.winid) then
    return
  end

  -- Check file size
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    self:close()
    return
  end
  local max_size = self.config.max_file_size
  if type(max_size) == "function" then
    max_size = max_size(path)
  end
  if stat.size > max_size then
    self:close()
    return
  end
  if is_binary(path) then
    self:close()
    return
  end

  -- Mark this path as pending for async guard
  self._pending_path = path

  -- Read file content asynchronously
  vim.uv.fs_open(path, "r", 438, function(err, fd)
    if err or not fd then
      return
    end
    vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
      vim.uv.fs_close(fd, function() end)
      if read_err or not data then
        return
      end
      vim.schedule(function()
        -- Guard against stale async callback
        if path ~= self._pending_path then
          return
        end
        if not self.window or not util.is_valid_win(self.window.winid) then
          return
        end

        -- Compute layout relative to filer window
        local Window = require("eda.window")
        local layout = Window._compute_preview_layout(self.window.kind, self.window.winid, self.window.config)
        if not layout then
          self:close()
          return
        end

        -- Create or reuse preview buffer
        if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
          self.bufnr = vim.api.nvim_create_buf(false, true)
          vim.bo[self.bufnr].bufhidden = "wipe"
        end

        -- Set file content
        local lines = vim.split(data, "\n", { plain = true })
        if #lines > 0 and lines[#lines] == "" then
          table.remove(lines)
        end
        vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

        -- Set filetype for syntax highlighting
        local ft = vim.filetype.match({ filename = path, buf = self.bufnr })
        if ft then
          vim.bo[self.bufnr].filetype = ft
        end

        -- Create or reuse preview window
        if not util.is_valid_win(self.winid) then
          -- Resize filer in float mode (first open only)
          if layout.filer then
            vim.api.nvim_win_set_config(self.window.winid, layout.filer)
          end
          self.winid = vim.api.nvim_open_win(self.bufnr, false, layout.preview)
        else
          vim.api.nvim_win_set_buf(self.winid, self.bufnr)
        end

        -- Reset scroll position when switching files
        if path ~= self._current_path then
          self._current_path = path
          if util.is_valid_win(self.winid) then
            vim.api.nvim_win_set_cursor(self.winid, { 1, 0 })
          end
        end
      end)
    end)
  end)
end

---Close the preview window.
function Preview:close()
  if util.is_valid_win(self.winid) then
    vim.api.nvim_win_close(self.winid, true)
  end
  self.winid = nil

  -- Restore filer to original size in float mode
  if self.window and self.window.kind == "float" and util.is_valid_win(self.window.winid) then
    local Window = require("eda.window")
    local orig = Window._compute_layout("float", self.window.config)
    vim.api.nvim_win_set_config(self.window.winid, {
      relative = orig.relative,
      width = orig.width,
      height = orig.height,
      row = orig.row,
      col = orig.col,
    })
  end
end

---Reposition preview window (e.g. after VimResized).
function Preview:reposition()
  if not util.is_valid_win(self.winid) then
    return
  end
  if not self.window or not util.is_valid_win(self.window.winid) then
    return
  end

  local Window = require("eda.window")
  local layout = Window._compute_preview_layout(self.window.kind, self.window.winid, self.window.config)
  if not layout then
    self:close()
    return
  end

  vim.api.nvim_win_set_config(self.winid, layout.preview)
  if layout.filer then
    vim.api.nvim_win_set_config(self.window.winid, layout.filer)
  end
end

---Scroll the preview window down by half a page.
---@return boolean true if scrolled, false if preview not visible
function Preview:scroll_down()
  if not util.is_valid_win(self.winid) then
    return false
  end
  vim.api.nvim_win_call(self.winid, function()
    vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<C-d>", true, false, true))
  end)
  return true
end

---Scroll the preview window up by half a page.
---@return boolean true if scrolled, false if preview not visible
function Preview:scroll_up()
  if not util.is_valid_win(self.winid) then
    return false
  end
  vim.api.nvim_win_call(self.winid, function()
    vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<C-u>", true, false, true))
  end)
  return true
end

---Scroll the preview window down by a full page.
---@return boolean true if scrolled, false if preview not visible
function Preview:scroll_page_down()
  if not util.is_valid_win(self.winid) then
    return false
  end
  vim.api.nvim_win_call(self.winid, function()
    vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<C-f>", true, false, true))
  end)
  return true
end

---Scroll the preview window up by a full page.
---@return boolean true if scrolled, false if preview not visible
function Preview:scroll_page_up()
  if not util.is_valid_win(self.winid) then
    return false
  end
  vim.api.nvim_win_call(self.winid, function()
    vim.cmd("normal! " .. vim.api.nvim_replace_termcodes("<C-b>", true, false, true))
  end)
  return true
end

---Update preview based on cursor node (debounced).
---@param node eda.TreeNode?
function Preview:update(node)
  if not self.config.enabled then
    return
  end

  if not node or node.type == "directory" then
    self:close()
    return
  end

  if not self._debounced then
    self._debounced = util.debounce(self.config.debounce, function(path)
      self:show(path)
    end)
  end

  self._debounced(node.path)
end

return Preview
