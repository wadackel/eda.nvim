local Node = require("eda.tree.node")
local util = require("eda.util")

---@class eda.Preview
---@field winid integer?
---@field bufnr integer?
---@field config eda.PreviewConfig
---@field window eda.Window?
---@field store eda.Store?
---@field scanner eda.Scanner?
---@field decorator_chain eda.DecoratorChain?
---@field painter eda.Painter?
---@field _debounced fun(node: eda.TreeNode)?
---@field _pending_target integer|string|nil  Node id (dir mode) or path string (file mode)
---@field _current_target integer|string|nil  Node id (dir mode) or path string (file mode)
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
    store = nil,
    scanner = nil,
    decorator_chain = nil,
    painter = nil,
    _debounced = nil,
    _pending_target = nil,
    _current_target = nil,
  }, Preview)
end

---Attach the filer window and (optionally) tree dependencies for directory preview.
---When `deps` is omitted, only file preview is supported.
---@param window eda.Window
---@param deps? { store: eda.Store, scanner: eda.Scanner, decorator_chain: eda.DecoratorChain }
function Preview:attach(window, deps)
  self.window = window
  if deps then
    self.store = deps.store
    self.scanner = deps.scanner
    self.decorator_chain = deps.decorator_chain
  end
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

---Ensure the preview buffer (and Painter) exist.
function Preview:_ensure_buffer()
  if not self.bufnr or not vim.api.nvim_buf_is_valid(self.bufnr) then
    self.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[self.bufnr].bufhidden = "wipe"
    self.painter = nil
  end
  if not self.painter then
    local cfg = require("eda.config").get()
    local indent_width = cfg.indent and cfg.indent.width or 2
    self.painter = require("eda.render.painter").new(self.bufnr, indent_width)
  end
end

---Open a fresh preview window or reuse the existing one.
---@param layout { preview: table, filer: table? }
function Preview:_open_or_reuse_window(layout)
  if not util.is_valid_win(self.winid) then
    -- Resize filer in float mode (first open only)
    if layout.filer then
      vim.api.nvim_win_set_config(self.window.winid, layout.filer)
    end
    self.winid = vim.api.nvim_open_win(self.bufnr, false, layout.preview)
  else
    vim.api.nvim_win_set_buf(self.winid, self.bufnr)
  end
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
  self._pending_target = path

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
        if self._pending_target ~= path then
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

        self:_ensure_buffer()
        -- Clear any stale tree-render state from a previous directory preview
        self.painter:reset()

        -- Set file content
        local lines = vim.split(data, "\n", { plain = true })
        if #lines > 0 and lines[#lines] == "" then
          table.remove(lines)
        end
        vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)

        -- Set filetype for syntax highlighting (clear when no match so transitions
        -- between files / directories do not leave stale filetype attached).
        local ft = vim.filetype.match({ filename = path, buf = self.bufnr })
        vim.bo[self.bufnr].filetype = ft or ""

        self:_open_or_reuse_window(layout)

        -- Reset scroll position when switching targets
        if path ~= self._current_target then
          self._current_target = path
          if util.is_valid_win(self.winid) then
            vim.api.nvim_win_set_cursor(self.winid, { 1, 0 })
          end
        end
      end)
    end)
  end)
end

---Show a directory preview using eda's tree-render style.
---@param node eda.TreeNode
function Preview:show_directory(node)
  if not self.config.enabled then
    return
  end
  if not self.window or not util.is_valid_win(self.window.winid) then
    return
  end
  if not self.store or not self.scanner or not self.decorator_chain then
    -- Tree deps not attached; cannot render directory preview.
    return
  end

  self._pending_target = node.id

  if node.children_state == "loaded" then
    self:_render_directory(node)
    return
  end

  self.scanner:scan(node.id, function()
    vim.schedule(function()
      if self._pending_target ~= node.id then
        return
      end
      local fresh = self.store:get(node.id)
      if not fresh or fresh.children_state ~= "loaded" then
        return
      end
      self:_render_directory(fresh)
    end)
  end)
end

---Paint the directory subtree into the preview buffer.
---@param node eda.TreeNode
function Preview:_render_directory(node)
  if self._pending_target ~= node.id then
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

  self:_ensure_buffer()
  self.painter:reset()
  vim.bo[self.bufnr].filetype = ""

  local cfg = require("eda.config").get()
  local root = self.store:get(self.store.root_id)
  local git_status = root and require("eda.git").get_cached(root.path) or nil

  local flat_lines = require("eda.render.flatten").flatten(self.store, node.id)
  local ctx = { store = self.store, git_status = git_status, config = cfg }
  local decorations = self.decorator_chain:decorate(flat_lines, ctx)

  self.painter:paint(flat_lines, decorations, {
    root_path = nil,
    header = false,
    kind = "preview",
    icon = cfg.icon,
  })

  self:_open_or_reuse_window(layout)

  if self._current_target ~= node.id then
    self._current_target = node.id
    if util.is_valid_win(self.winid) then
      vim.api.nvim_win_set_cursor(self.winid, { 1, 0 })
    end
  end
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

---Update preview based on cursor node (debounced). Routes directories to the
---tree-render path and files to the byte-content path.
---@param node eda.TreeNode?
function Preview:update(node)
  if not self.config.enabled then
    return
  end

  if not node then
    self:close()
    return
  end

  if not self._debounced then
    self._debounced = util.debounce(self.config.debounce, function(target)
      if Node.is_dir(target) then
        self:show_directory(target)
      else
        self:show(target.path)
      end
    end)
  end

  self._debounced(node)
end

return Preview
