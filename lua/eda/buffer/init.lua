local Painter = require("eda.render.painter")
local Flatten = require("eda.render.flatten")
local util = require("eda.util")

---@class eda.Buffer
---@field bufnr integer
---@field painter eda.Painter
---@field config eda.Config
---@field flat_lines eda.FlatLine[]
---@field target_node_id integer?
---@field focus_node_id integer?
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
    focus_node_id = nil,
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

---Restore cursor to the navigation target.
---`focus_node_id` (set by external navigation events that jump to a possibly-far
---node) wins over `target_node_id` (set by save_cursor for in-place preserve).
---When `focus_node_id` is the source, the viewport is centered with `zz` so the
---target line lands at the middle of the window instead of the edge — Neovim's
---auto-center on large jumps clamps near EOF and pushes the cursor to the
---bottom, which is the symptom this branch fixes.
function Buffer:restore_cursor()
  local node_id = self.focus_node_id or self.target_node_id
  if not node_id then
    return
  end
  local should_center = self.focus_node_id ~= nil
  local header_lines = self.painter.header_lines or 0
  for i, fl in ipairs(self.flat_lines) do
    if fl.node_id == node_id then
      local target_row = i + header_lines
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == self.bufnr then
          if not vim.api.nvim_win_is_valid(win) then
            return
          end
          local line_count = vim.api.nvim_buf_line_count(self.bufnr)
          if target_row <= line_count then
            vim.api.nvim_win_set_cursor(win, { target_row, 0 })
            if should_center then
              vim.api.nvim_win_call(win, function()
                vim.cmd("normal! zz")
              end)
            end
          end
          return
        end
      end
      return
    end
  end
end

---Resolve a range of buffer rows to nodes, in row order.
---Rows carrying no node — header rows, blank rows, and lines the user typed that
---have not been saved yet — are skipped, so the result may be shorter than the range.
---When the buffer has been modified (lines inserted/deleted), flat_lines indices
---are stale. Uses ns_ids extmarks as the source of truth for line-to-node mapping.
---@param start_row integer 1-based buffer row, header rows included in the numbering
---@param end_row integer 1-based buffer row, inclusive
---@return eda.TreeNode[]
function Buffer:get_nodes_in_rows(start_row, end_row)
  start_row = math.max(start_row, 1)
  if end_row < start_row then
    return {}
  end

  local nodes = {}

  -- When buffer is not modified, flat_lines indices are reliable
  if not vim.bo[self.bufnr].modified then
    local header_lines = self.painter.header_lines or 0
    for row = start_row, end_row do
      local fl = self.flat_lines[row - header_lines]
      if fl then
        nodes[#nodes + 1] = fl.node
      end
    end
    return nodes
  end

  end_row = math.min(end_row, vim.api.nvim_buf_line_count(self.bufnr))
  if end_row < start_row then
    return {}
  end

  local by_id = {}
  for _, fl in ipairs(self.flat_lines) do
    by_id[fl.node_id] = fl
  end

  -- Buffer is modified: use extmarks to find the node on each row.
  -- Extmarks track line shifts from insert/delete operations. We must request
  -- `details = true` so we can skip extmarks whose underlying line was replaced
  -- (those report `invalid = true` per the same convention used in
  -- Painter:_resync_on_redraw).
  -- The whole row is queried rather than column 0: ns_ids marks have the default
  -- right_gravity, so text typed at the start of a line pushes the mark off column 0.
  local marks = vim.api.nvim_buf_get_extmarks(
    self.bufnr,
    self.painter.ns_ids,
    { start_row - 1, 0 },
    { end_row - 1, -1 },
    { details = true }
  )
  local resolved_row = {}
  for _, m in ipairs(marks) do
    local row = m[2]
    if not resolved_row[row] and not (m[4] and m[4].invalid) then
      local fl = by_id[m[1]]
      if fl then
        resolved_row[row] = true
        nodes[#nodes + 1] = fl.node
      end
    end
  end

  return nodes
end

---Get the node at the current cursor position.
---@param winid integer
---@return eda.TreeNode?
function Buffer:get_cursor_node(winid)
  if not util.is_valid_win(winid) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(winid)[1]
  return self:get_nodes_in_rows(row, row)[1]
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
  delete = true,
  duplicate = true,
  quickfix = true,
  mark_toggle = true,
  yank_tree = true,
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
      pcall(vim.keymap.del, "v", key, { buffer = self.bufnr })
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
