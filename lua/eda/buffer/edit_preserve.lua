local Parser = require("eda.buffer.parser")
local Diff = require("eda.tree.diff")

local M = {}

---@class eda.EditCapture
---@field moves table<integer, string> node_id → edited buffer line text
---@field deletes table<integer, true> node_id → true
---@field creates eda.CreateCapture[] new user-typed entries
---@field operations eda.Operation[] raw Diff.compute output

---@class eda.CreateCapture
---@field text string raw buffer line text
---@field prev_node_id integer? nearest extmark-bearing line above (primary anchor)
---@field parent_path string from parser (fallback anchor)
---@field indent integer depth level (fallback anchor)

---Check whether a capture contains any edits.
---@param capture eda.EditCapture
---@return boolean
function M.has_edits(capture)
  return next(capture.moves) ~= nil or next(capture.deletes) ~= nil or #capture.creates > 0
end

---Capture user edits from the current dirty buffer.
---@param bufnr integer
---@param painter eda.Painter
---@param store eda.Store
---@param root_path string
---@param indent_width integer
---@return eda.EditCapture
function M.capture(bufnr, painter, store, root_path, indent_width)
  local ns_id = painter.ns_ids
  local header_lines = painter.header_lines or 0

  local parsed = Parser.parse_lines(bufnr, ns_id, indent_width, root_path, header_lines)
  local snapshot = painter:get_snapshot()
  local operations = Diff.compute(parsed, snapshot, store)

  local moves = {}
  local deletes = {}
  local creates = {}

  -- Build lookup tables in a single pass for O(1) operation processing
  local index_by_node_id = {} -- node_id -> 1-based index in parsed array
  for i, pl in ipairs(parsed) do
    if pl.node_id then
      index_by_node_id[pl.node_id] = i
    end
  end

  local snap_path_to_id = {} -- snapshot path -> node_id
  for node_id, entry in pairs(snapshot.entries) do
    snap_path_to_id[entry.path] = node_id
  end

  for _, op in ipairs(operations) do
    if op.type == "move" then
      -- Look up node_id by op.src (the old path from snapshot)
      local node_id = snap_path_to_id[op.src]
      if node_id then
        local idx = index_by_node_id[node_id]
        if idx then
          local row = header_lines + idx - 1
          local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
          if line then
            moves[node_id] = line
          end
        end
      end
    elseif op.type == "delete" then
      local node_id = snap_path_to_id[op.path]
      if node_id then
        deletes[node_id] = true
      end
    end
  end

  -- Collect CREATE entries: parsed lines without node_id
  for i, pl in ipairs(parsed) do
    if not pl.node_id and pl.name ~= "" then
      local row = header_lines + i - 1
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
      if line then
        -- Find prev_node_id: scan upward for nearest extmark-bearing line
        local prev_node_id = nil
        for j = i - 1, 1, -1 do
          if parsed[j].node_id then
            prev_node_id = parsed[j].node_id
            break
          end
        end

        table.insert(creates, {
          text = line,
          prev_node_id = prev_node_id,
          parent_path = pl.parent_path,
          indent = pl.indent,
        })
      end
    end
  end

  return {
    moves = moves,
    deletes = deletes,
    creates = creates,
    operations = operations,
  }
end

---Replay captured edits onto the freshly repainted buffer.
---@param bufnr integer
---@param painter eda.Painter
---@param capture eda.EditCapture
---@param store eda.Store
---@return boolean true if edits were replayed
function M.replay(bufnr, painter, capture, store)
  if not M.has_edits(capture) then
    return false
  end

  local ns_id = painter.ns_ids

  -- Suppress TextChanged autocmd during replay
  painter._replaying = true

  -- Suppress undo entries (same pattern as paint() L253-256)
  local saved_undo = vim.bo[bufnr].undolevels
  vim.bo[bufnr].undolevels = -1

  -- 1. MOVE: replace line text (no row count change)
  for node_id, text in pairs(capture.moves) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, node_id, {})
    if pos and pos[1] then
      vim.api.nvim_buf_set_lines(bufnr, pos[1], pos[1] + 1, false, { text })
    end
  end

  -- 2. DELETE: remove lines in reverse row order
  local delete_rows = {}
  for node_id, _ in pairs(capture.deletes) do
    local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, node_id, {})
    if pos and pos[1] then
      table.insert(delete_rows, pos[1])
    end
  end
  table.sort(delete_rows, function(a, b)
    return a > b
  end)
  for _, row in ipairs(delete_rows) do
    vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, {})
  end

  -- 3. CREATE: insert lines (one at a time, re-fetching extmark positions)
  -- Track insertion offsets per anchor to preserve ordering of consecutive CREATEs
  -- sharing the same prev_node_id (e.g., `o foo`, `o bar` both anchor to file_a)
  local anchor_offsets = {}
  for _, cr in ipairs(capture.creates) do
    local insert_row = nil

    -- Primary anchor: prev_node_id
    if cr.prev_node_id then
      local anchor_id = cr.prev_node_id --[[@as integer]]
      local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, anchor_id, {})
      local anchor_row = pos and pos[1]

      -- If anchor not visible (e.g. parent directory collapsed), walk up the parent chain
      if not anchor_row then
        local node = store:get(cr.prev_node_id)
        while node and node.parent_id do
          ---@diagnostic disable-next-line: need-check-nil
          node = store:get(node.parent_id)
          if node then
            local p = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, node.id, {})
            if p and p[1] then
              anchor_id = node.id
              anchor_row = p[1]
              break
            end
          end
        end
      end

      if anchor_row then
        -- If anchor is an open, loaded directory, skip past its visible descendants
        local anchor_node = store:get(anchor_id)
        if anchor_node and anchor_node.open and anchor_node.children_state == "loaded" then
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          local prefix = anchor_node.path .. "/"
          for r = anchor_row + 1, line_count - 1 do
            local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { r, 0 }, { r, -1 }, {})
            if #marks > 0 then
              local mark_node = store:get(marks[1][1])
              if mark_node and mark_node.path:sub(1, #prefix) == prefix then
                anchor_row = r
              else
                break
              end
            else
              -- No extmark: could be a previously inserted CREATE line, keep walking
              anchor_row = r
            end
          end
        end

        local offset = anchor_offsets[cr.prev_node_id] or 0
        insert_row = anchor_row + 1 + offset
        anchor_offsets[cr.prev_node_id] = offset + 1
      end
    end

    -- Fallback anchor: parent directory
    if not insert_row and cr.parent_path then
      local parent_node = store:get_by_path(cr.parent_path)
      if parent_node then
        local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns_id, parent_node.id, {})
        if pos and pos[1] then
          -- Insert after parent's last visible child
          -- Walk forward from parent row until indent drops
          local parent_row = pos[1]
          local line_count = vim.api.nvim_buf_line_count(bufnr)
          local last_child_row = parent_row
          for r = parent_row + 1, line_count - 1 do
            local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { r, 0 }, { r, -1 }, {})
            if #marks > 0 then
              -- Check if this row is a descendant of the parent
              local mark_node = store:get(marks[1][1])
              if mark_node then
                local mark_path = mark_node.path
                local prefix = cr.parent_path .. "/"
                if mark_path:sub(1, #prefix) == prefix then
                  last_child_row = r
                else
                  break
                end
              else
                break
              end
            else
              -- No extmark on this row — could be another CREATE line, keep going
              last_child_row = r
            end
          end
          insert_row = last_child_row + 1
        end
      end
    end

    -- Skip if no anchor found (parent collapsed/hidden)
    if insert_row then
      vim.api.nvim_buf_set_lines(bufnr, insert_row, insert_row, false, { cr.text })
    end
  end

  -- Restore undo levels
  vim.bo[bufnr].undolevels = saved_undo

  -- Re-enable TextChanged handling
  painter._replaying = false

  -- Resync caches
  painter:resync_highlights()

  -- Mark buffer as modified
  vim.bo[bufnr].modified = true

  return true
end

return M
