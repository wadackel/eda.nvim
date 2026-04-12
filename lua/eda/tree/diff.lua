local M = {}

---@class eda.Operation
---@field type "create"|"delete"|"move"
---@field path string
---@field src string?
---@field dst string?
---@field entry_type "file"|"directory"?

---Compute operations by comparing parsed buffer lines against the render snapshot.
---@param parsed_lines eda.ParsedLine[] Output from parser.parse_lines
---@param snapshot eda.RenderSnapshot The snapshot from the last render
---@param store eda.Store
---@return eda.Operation[]
function M.compute(parsed_lines, snapshot, store)
  local operations = {}

  -- Build set of node_ids present in parsed lines
  local parsed_ids = {}
  for _, pl in ipairs(parsed_lines) do
    if pl.node_id then
      parsed_ids[pl.node_id] = pl
    end
  end

  -- 1. Check for DELETEs: node_ids in snapshot but not in parsed
  local deletes = {}
  for node_id, entry in pairs(snapshot.entries) do
    if not parsed_ids[node_id] then
      local node = store:get(node_id)
      if node then
        table.insert(deletes, {
          type = "delete",
          path = entry.path,
          entry_type = node.type == "directory" and "directory" or "file",
        })
      end
    end
  end

  -- 2. Check for MOVEs and CREATEs
  local moves = {}
  local creates = {}
  for _, pl in ipairs(parsed_lines) do
    if pl.node_id then
      -- Existing node: check if path changed → MOVE
      local snap_entry = snapshot.entries[pl.node_id]
      if snap_entry and snap_entry.path ~= pl.full_path then
        table.insert(moves, {
          type = "move",
          path = pl.full_path,
          src = snap_entry.path,
          dst = pl.full_path,
        })
      end
    else
      -- No extmark → CREATE (even if name matches an existing node)
      table.insert(creates, {
        type = "create",
        path = pl.full_path,
        entry_type = pl.is_dir and "directory" or "file",
      })
    end
  end

  -- Order: MOVE → DELETE (children before parents) → CREATE (parents before children)
  -- Sort deletes: longer paths first (children before parents)
  table.sort(deletes, function(a, b)
    return #a.path > #b.path
  end)

  -- Sort creates: shorter paths first (parents before children)
  table.sort(creates, function(a, b)
    return #a.path < #b.path
  end)

  for _, op in ipairs(moves) do
    table.insert(operations, op)
  end
  for _, op in ipairs(deletes) do
    table.insert(operations, op)
  end
  for _, op in ipairs(creates) do
    table.insert(operations, op)
  end

  return operations
end

---Validate operations before execution.
---@param operations eda.Operation[]
---@param _store eda.Store
---@return { valid: boolean, errors: string[] }
function M.validate(operations, _store)
  local errors = {}

  for _, op in ipairs(operations) do
    if op.type == "move" then
      if not op.src or not op.dst then
        table.insert(errors, "Move operation missing src or dst")
      elseif op.src == op.dst then
        table.insert(errors, "Move operation has same src and dst: " .. op.src)
      end
    end
  end

  -- Check for duplicate destination paths
  local dst_paths = {}
  for _, op in ipairs(operations) do
    local dst
    if op.type == "move" then
      dst = op.dst
    elseif op.type == "create" then
      dst = op.path
    end
    if dst then
      if dst_paths[dst] then
        table.insert(errors, "Duplicate destination path: " .. dst)
      end
      dst_paths[dst] = true
    end
  end

  return {
    valid = #errors == 0,
    errors = errors,
  }
end

return M
