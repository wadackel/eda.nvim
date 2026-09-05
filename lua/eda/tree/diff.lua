local util = require("eda.util")

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
          entry_type = pl.is_dir and "directory" or "file",
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

  local moves_by_src = {}
  for _, op in ipairs(moves) do
    if op.entry_type == "directory" then
      moves_by_src[op.src] = op
    end
  end
  moves = vim.tbl_filter(function(op)
    local parent = vim.fn.fnamemodify(op.src, ":h")
    while parent ~= op.src do
      local ancestor = moves_by_src[parent]
      if ancestor then
        -- Moving the ancestor already relocates unchanged descendants on disk.
        return op.dst ~= ancestor.dst .. op.src:sub(#parent + 1)
      end
      local next_parent = vim.fn.fnamemodify(parent, ":h")
      if next_parent == parent then
        break
      end
      parent = next_parent
    end
    return true
  end, moves)

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

local function contains(parent, path)
  return parent == path or (parent == "/" and path:sub(1, 1) == "/") or path:sub(1, #parent + 1) == parent .. "/"
end

local function overlaps(a, b)
  return a and b and (contains(a, b) or contains(b, a))
end

local function path_key(path, parents)
  if not path then
    return nil
  end
  local tail = vim.fn.fnamemodify(path, ":t")
  local parent = vim.fn.fnamemodify(path, ":h")
  while true do
    local resolved = parents[parent]
    if resolved == nil then
      resolved = vim.uv.fs_realpath(parent) or false
      parents[parent] = resolved
    end
    if resolved then
      return util.nfc_normalize(vim.fs.normalize(resolved .. "/" .. tail))
    end
    local next_parent = vim.fn.fnamemodify(parent, ":h")
    if next_parent == parent then
      return util.nfc_normalize(vim.fs.normalize(path))
    end
    tail = vim.fn.fnamemodify(parent, ":t") .. "/" .. tail
    parent = next_parent
  end
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
    elseif op.type == "create" and vim.uv.fs_lstat(op.path) then
      table.insert(errors, "Create destination already exists: " .. op.path)
    end
  end

  if #errors > 0 then
    return { valid = false, errors = errors }
  end

  local paths, destinations, parents, sources = {}, {}, {}, {}
  for i, op in ipairs(operations) do
    local src = path_key(op.type == "delete" and op.path or op.src, parents)
    local dst = path_key(op.type == "create" and op.path or op.dst, parents)
    paths[i] = { src = src, dst = dst }
    if src then
      if sources[src] then
        errors[#errors + 1] = "Source scheduled more than once: " .. (op.src or op.path)
      end
      sources[src] = true
    end
    if dst then
      if destinations[dst] then
        errors[#errors + 1] = "Duplicate destination path: " .. (op.dst or op.path)
      end
      destinations[dst] = true
    end
    if op.type == "move" and overlaps(src, dst) then
      errors[#errors + 1] = "Move source and destination overlap: " .. op.path
    end
  end
  if #errors > 0 then
    return { valid = false, errors = errors }
  end
  local function check_pair(i, j)
    local a, b = operations[i], operations[j]
    local ap, bp = paths[i], paths[j]
    local conflict = overlaps(ap.dst, bp.src) or overlaps(bp.dst, ap.src)
    if overlaps(ap.src, bp.src) and not (a.type == "delete" and b.type == "delete") then
      local extracting = a.type == "move" and b.type == "delete" and ap.src ~= bp.src and contains(bp.src, ap.src)
        or b.type == "move" and a.type == "delete" and ap.src ~= bp.src and contains(ap.src, bp.src)
      conflict = conflict or not extracting
    end
    if overlaps(ap.dst, bp.dst) then
      local creating_children = a.type == "create"
        and b.type == "create"
        and ap.dst ~= bp.dst
        and (
          (contains(ap.dst, bp.dst) and a.entry_type == "directory")
          or (contains(bp.dst, ap.dst) and b.entry_type == "directory")
        )
      conflict = conflict or not creating_children
    end
    if conflict then
      errors[#errors + 1] = "Overlapping operations must be saved separately: " .. a.path .. " and " .. b.path
    end
  end

  local ordered = {}
  for i, path in ipairs(paths) do
    if path.src then
      ordered[#ordered + 1] = { path = path.src, index = i }
    end
    if path.dst then
      ordered[#ordered + 1] = { path = path.dst, index = i }
    end
  end
  -- A sibling such as src-extra must not sort between src and src/file.
  table.sort(ordered, function(a, b)
    return a.path .. "/" < b.path .. "/"
  end)
  local ancestors, checked = {}, {}
  for _, entry in ipairs(ordered) do
    while #ancestors > 0 and not contains(ancestors[#ancestors].path, entry.path) do
      table.remove(ancestors)
    end
    for _, ancestor in ipairs(ancestors) do
      if ancestor.index ~= entry.index then
        local i, j = math.min(ancestor.index, entry.index), math.max(ancestor.index, entry.index)
        local key = i .. ":" .. j
        if not checked[key] then
          checked[key] = true
          check_pair(i, j)
        end
      end
    end
    ancestors[#ancestors + 1] = entry
  end

  return {
    valid = #errors == 0,
    errors = errors,
  }
end

return M
