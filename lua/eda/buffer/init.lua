local Painter = require("eda.render.painter")
local Flatten = require("eda.render.flatten")
local util = require("eda.util")

---@class eda.Buffer
---@field bufnr integer
---@field painter eda.Painter
---@field config eda.Config
---@field flat_lines eda.FlatLine[]
---@field target_node_id integer?
---@field _augroup integer
---@field _write_handler fun()?
local Buffer = {}
Buffer.__index = Buffer

---Create a new eda buffer.
---@param root_path string
---@param config eda.Config
---@param instance_id? integer Optional instance ID for split buffers (appended as #<id>)
---@return eda.Buffer
function Buffer.new(root_path, config, instance_id)
  local bufnr = vim.api.nvim_create_buf(false, false)
  -- Disable swap before set_name: prevents E325/E95 when another nvim has the same
  -- eda://<path> buffer active, or when a stale swap file remains on disk from a crash.
  vim.bo[bufnr].swapfile = false

  local name = "eda://" .. root_path
  if instance_id then
    name = name .. "#" .. instance_id
  end

  vim.api.nvim_buf_set_name(bufnr, name)

  -- Apply buf_opts
  for k, v in pairs(config.window.buf_opts) do
    vim.bo[bufnr][k] = v
  end
  -- Re-enforce after buf_opts: a user-supplied swapfile=true must not re-enable swap.
  vim.bo[bufnr].swapfile = false

  -- Sync Neovim indent options with tree indent width so that native
  -- indent operations (>>, <<, <Tab>) match the visual tree indentation.
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].shiftwidth = config.indent.width
  vim.bo[bufnr].tabstop = config.indent.width

  local painter = Painter.new(bufnr, config.indent.width)

  local self = setmetatable({
    bufnr = bufnr,
    painter = painter,
    config = config,
    flat_lines = {},
    target_node_id = nil,
    _augroup = vim.api.nvim_create_augroup("eda_buffer_" .. bufnr, { clear = true }),
    _write_handler = nil,
  }, Buffer)

  -- CursorMoved: constrain cursor to content area
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = self._augroup,
    buffer = bufnr,
    callback = function()
      self:_constrain_cursor()
    end,
  })

  -- TextChanged: resync icon extmarks and caches after user edits (e.g. dd)
  vim.api.nvim_create_autocmd("TextChanged", {
    group = self._augroup,
    buffer = bufnr,
    callback = function()
      if painter._replaying then
        return
      end
      painter:resync_highlights()
    end,
  })

  -- BufWriteCmd: delegates to write handler set by init.lua
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = self._augroup,
    buffer = bufnr,
    callback = function()
      if self._write_handler then
        self._write_handler()
      else
        vim.bo[bufnr].modified = false
      end
    end,
  })

  return self
end

---Render the tree into the buffer.
---@param store eda.Store
---@param decorations? eda.Decoration[]
function Buffer:render(store, decorations)
  self.flat_lines = Flatten.flatten(store, store.root_id)

  -- Build per-line decorations array if not provided
  local decs = decorations
  if not decs then
    decs = {}
    for i = 1, #self.flat_lines do
      decs[i] = nil
    end
  end

  self.painter:paint(self.flat_lines, decs)
  self:restore_cursor()
end

---Save cursor position as target_node_id.
---@param winid integer
function Buffer:save_cursor(winid)
  if not util.is_valid_win(winid) then
    return
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  local header_lines = self.painter.header_lines or 0
  local fl = self.flat_lines[row - header_lines]
  if fl then
    self.target_node_id = fl.node_id
  end
end

---Restore cursor to target_node_id position.
function Buffer:restore_cursor()
  if not self.target_node_id then
    return
  end
  local header_lines = self.painter.header_lines or 0
  for i, fl in ipairs(self.flat_lines) do
    if fl.node_id == self.target_node_id then
      -- Find the window displaying this buffer
      local target_row = i + header_lines
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == self.bufnr then
          local line_count = vim.api.nvim_buf_line_count(self.bufnr)
          if target_row <= line_count then
            vim.api.nvim_win_set_cursor(win, { target_row, 0 })
          end
          return
        end
      end
      return
    end
  end
end

---Get the node at the current cursor position.
---When the buffer has been modified (lines inserted/deleted), flat_lines indices
---are stale. Uses ns_ids extmarks as the source of truth for line-to-node mapping.
---@param winid integer
---@return eda.TreeNode?
function Buffer:get_cursor_node(winid)
  if not util.is_valid_win(winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  local header_lines = self.painter.header_lines or 0

  -- When buffer is not modified, flat_lines indices are reliable
  if not vim.bo[self.bufnr].modified then
    local fl = self.flat_lines[row - header_lines]
    if fl then
      return fl.node
    end
    return nil
  end

  -- Buffer is modified: use extmarks to find the node at the cursor row.
  -- Extmarks track line shifts from insert/delete operations. We must request
  -- `details = true` so we can skip extmarks whose underlying line was replaced
  -- (those report `invalid = true` per the same convention used in
  -- Painter:_resync_on_redraw).
  local marks = vim.api.nvim_buf_get_extmarks(
    self.bufnr,
    self.painter.ns_ids,
    { row - 1, 0 },
    { row - 1, 0 },
    { details = true }
  )
  for _, m in ipairs(marks) do
    if not (m[4] and m[4].invalid) then
      local node_id = m[1]
      for _, f in ipairs(self.flat_lines) do
        if f.node_id == node_id then
          return f.node
        end
      end
    end
  end

  return nil
end

---Get the FlatLine at the current cursor position.
---@param winid integer
---@return eda.FlatLine?
function Buffer:get_cursor_flat_line(winid)
  if not util.is_valid_win(winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  local header_lines = self.painter.header_lines or 0
  return self.flat_lines[row - header_lines]
end

---Constrain cursor to stay in the content area (after indent and below header).
function Buffer:_constrain_cursor()
  local header_lines = self.painter.header_lines or 0
  local min_row = header_lines + 1
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == self.bufnr then
      local cursor = vim.api.nvim_win_get_cursor(win)
      local row = cursor[1]
      local col = cursor[2]

      -- Prevent cursor from moving onto header lines
      if row < min_row then
        vim.api.nvim_win_set_cursor(win, { min_row, col })
        row = min_row
      end

      local fl = self.flat_lines[row - header_lines]
      if fl then
        local min_col = fl.depth * self.config.indent.width
        if col < min_col then
          vim.api.nvim_win_set_cursor(win, { row, min_col })
        end
      end
    end
  end
end

-- Actions that support visual mode selection.
local visual_mode_actions = {
  cut = true,
  copy = true,
  quickfix = true,
  mark_toggle = true,
}

---Set keymaps on the buffer.
---@param mappings table<string, eda.MappingValue>
---@param dispatch fun(action_name: string)
---@param get_public_ctx? fun(): eda.PublicContext
function Buffer:set_mappings(mappings, dispatch, get_public_ctx)
  for key, mapping in pairs(mappings) do
    local action_value, desc
    if type(mapping) == "table" then
      action_value = mapping.action
      desc = mapping.desc
    else
      action_value = mapping
    end

    if action_value == false then
      pcall(vim.keymap.del, "n", key, { buffer = self.bufnr })
    elseif type(action_value) == "function" then
      local fn = action_value
      vim.keymap.set("n", key, function()
        if get_public_ctx then
          fn(get_public_ctx())
        else
          fn()
        end
      end, { buffer = self.bufnr, nowait = true, silent = true, desc = desc })
    elseif type(action_value) == "string" then
      local modes = visual_mode_actions[action_value] and { "n", "v" } or "n"
      vim.keymap.set(modes, key, function()
        dispatch(action_value)
      end, { buffer = self.bufnr, nowait = true, silent = true, desc = desc })
    end
  end
end

---Set the write handler for BufWriteCmd.
---@param handler fun()
function Buffer:set_write_handler(handler)
  self._write_handler = handler
end

---Destroy the buffer and clean up.
function Buffer:destroy()
  pcall(vim.api.nvim_del_augroup_by_id, self._augroup)
  if util.is_valid_buf(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

return Buffer
