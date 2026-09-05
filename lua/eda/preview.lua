local Node = require("eda.tree.node")
local image = require("eda.preview.image")
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
---@field _debounced eda.Debounce?
---@field _request_id integer
---@field _pending_target integer|string|nil  Node id (dir mode) or path string (file mode)
---@field _current_target integer|string|nil  Node id (dir mode) or path string (file mode)
local Preview = {}
Preview.__index = Preview

-- bufhidden=wipe cannot free a buffer when presentation was cancelled before its first window opened.
---@param bufnr integer?
local function wipe_hidden_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

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
    _request_id = 0,
    _pending_target = nil,
    _current_target = nil,
  }, Preview)
end

---Attach the filer window and (optionally) tree dependencies for directory preview.
---When `deps` is omitted, only file preview is supported.
---@param window eda.Window
---@param deps? { store: eda.Store, scanner: eda.Scanner, decorator_chain: eda.DecoratorChain }
function Preview:attach(window, deps)
  self:close()
  self.window = window
  self.store = deps and deps.store or nil
  self.scanner = deps and deps.scanner or nil
  self.decorator_chain = deps and deps.decorator_chain or nil
end

---@param target integer|string?
---@return integer
function Preview:_begin_request(target)
  self._request_id = self._request_id + 1
  self._pending_target = target
  if self._debounced then
    self._debounced.cancel()
  end
  return self._request_id
end

---@param target integer|string
---@param request_id integer
---@return boolean
function Preview:_is_current(target, request_id)
  return self.config.enabled and self._pending_target == target and self._request_id == request_id
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
  -- Every render path reuses this buffer, so an image shown for the previous target is freed here
  image.detach(self.bufnr)
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
    self:close()
    return
  end

  if not self.window or not util.is_valid_win(self.window.winid) then
    return
  end

  local request_id = self:_begin_request(path)

  -- Check file size
  local stat = vim.uv.fs_stat(path)
  if not stat or stat.type ~= "file" then
    self:close()
    return
  end
  -- Images bypass max_file_size and binary detection; they carry their own limit
  local image_cfg = self.config.image
  if type(image_cfg) == "table" and image_cfg.enabled and image.is_image(path) then
    self:_show_image(path, stat, request_id)
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
        self:_present(path, request_id, {
          fill = function(bufnr)
            local lines = vim.split(data, "\n", { plain = true })
            if #lines > 0 and lines[#lines] == "" then
              table.remove(lines)
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            -- Clear the filetype when nothing matches so transitions between files and
            -- directories do not leave a stale one attached.
            local ft = vim.filetype.match({ filename = path, buf = bufnr })
            vim.bo[bufnr].filetype = ft or ""
          end,
        })
      end)
    end)
  end)
end

---Show an image preview. The window is opened before rendering so the image
---backend can size its placement against the visible preview window.
---@param path string
---@param stat uv.fs_stat.result
---@param request_id integer
function Preview:_show_image(path, stat, request_id)
  local limit = self.config.image.max_file_size
  if stat.size > limit then
    self:_present(path, request_id, {
      fill = function(bufnr)
        vim.bo[bufnr].filetype = ""
        image.describe(bufnr, path, string.format("Image exceeds preview.image.max_file_size (%d bytes).", limit))
      end,
    })
    return
  end

  self:_present(path, request_id, {
    fill = function(bufnr)
      vim.bo[bufnr].filetype = ""
      image.loading(bufnr, path)
    end,
    after = function(bufnr, winid)
      image.render(bufnr, winid, path, function()
        return self:_is_current(path, request_id) and self.bufnr == bufnr and self.winid == winid
      end, { transmission = self.config.image.transmission })
    end,
  })
end

---@class eda.PreviewPresentOpts
---@field fill fun(bufnr: integer) writes the buffer content for the target
---@field after? fun(bufnr: integer, winid: integer) runs once the preview window is visible

---@param target integer|string
---@param request_id integer
---@param opts eda.PreviewPresentOpts
function Preview:_present(target, request_id, opts)
  if not self:_is_current(target, request_id) then
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
  local bufnr = assert(self.bufnr, "preview buffer was not created")
  opts.fill(bufnr)

  if not self:_is_current(target, request_id) then
    wipe_hidden_buffer(bufnr)
    return
  end

  self:_open_or_reuse_window(layout)

  if target ~= self._current_target then
    self._current_target = target
    if util.is_valid_win(self.winid) then
      vim.api.nvim_win_set_cursor(self.winid, { 1, 0 })
    end
  end

  if opts.after and self.bufnr and self.winid then
    opts.after(self.bufnr, self.winid)
  end
end

---Show a directory preview using eda's tree-render style.
---@param node eda.TreeNode
function Preview:show_directory(node)
  if not self.config.enabled then
    self:close()
    return
  end
  if not self.window or not util.is_valid_win(self.window.winid) then
    return
  end
  local store, scanner = self.store, self.scanner
  if not store or not scanner or not self.decorator_chain then
    self:close()
    return
  end

  local request_id = self:_begin_request(node.id)

  if node.children_state == "loaded" then
    self:_render_directory(node, request_id)
    return
  end

  scanner:scan(node.id, function()
    vim.schedule(function()
      if not self:_is_current(node.id, request_id) or self.store ~= store then
        return
      end
      local fresh = store:get(node.id)
      if not fresh or fresh.children_state ~= "loaded" then
        return
      end
      self:_render_directory(fresh, request_id)
    end)
  end)
end

---Paint the directory subtree into the preview buffer.
---@param node eda.TreeNode
---@param request_id integer
function Preview:_render_directory(node, request_id)
  self:_present(node.id, request_id, {
    fill = function(bufnr)
      vim.bo[bufnr].filetype = ""

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
    end,
  })
end

---Close the preview window.
function Preview:close()
  local winid, bufnr = self.winid, self.bufnr
  self:_begin_request(nil)
  self._current_target = nil
  if self._debounced then
    self._debounced.dispose()
    self._debounced = nil
  end
  self.winid = nil
  self.bufnr = nil
  self.painter = nil
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    image.detach(bufnr)
  end
  if winid and util.is_valid_win(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  wipe_hidden_buffer(bufnr)

  -- Restore filer to original size in float mode
  if winid and self.window and self.window.kind == "float" and util.is_valid_win(self.window.winid) then
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
  if self.bufnr then
    image.reposition(self.bufnr, self.winid)
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
    self:close()
    return
  end

  if not node then
    self:close()
    return
  end

  self:_begin_request(nil)

  if not self._debounced then
    self._debounced = util.debounce(self.config.debounce, function(target)
      if Node.is_dir(target) then
        self:show_directory(target)
      else
        self:show(target.path)
      end
    end)
  end

  self._debounced.call(node)
end

return Preview
