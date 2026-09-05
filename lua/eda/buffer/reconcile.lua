local util = require("eda.util")

local M = {}

local function contains(parent, path)
  return parent == path or path:sub(1, #parent + 1) == parent .. "/"
end

---@param buffer eda.Buffer
---@param store eda.Store
---@param completed eda.Operation[]
---@param parsed eda.ParsedLine[]
function M.apply(buffer, store, completed, parsed)
  local snapshot = buffer.painter:get_snapshot()
  local root = assert(store:get(store.root_id))
  local entries_by_path = {}
  for _, entry in ipairs(parsed) do
    entries_by_path[entry.full_path] = entry
  end

  local function remove(path)
    for id, entry in pairs(snapshot.entries) do
      if contains(path, entry.path) then
        snapshot.entries[id] = nil
      end
    end
    local node = store:get_by_path(path)
    if node then
      store:remove(node.id)
    end
  end

  for _, op in ipairs(completed) do
    if op.type == "delete" then
      remove(op.path)
    elseif op.type == "move" then
      remove(op.dst)
      local node = store:get_by_path(op.src)
      local parsed_entry = entries_by_path[op.dst]
      if node then
        local old_parent = store:get(node.parent_id)
        local parent = store:get_by_path(parsed_entry.parent_path) or root
        if old_parent and old_parent.id ~= parent.id then
          for i, id in ipairs(old_parent.children_ids or {}) do
            if id == node.id then
              table.remove(old_parent.children_ids, i)
              break
            end
          end
          parent.children_ids = parent.children_ids or {}
          table.insert(parent.children_ids, node.id)
          node.parent_id = parent.id
        end
        node.name = parsed_entry.name
        for _, child in pairs(store.nodes) do
          if contains(op.src, child.path) then
            store.path_index[util.nfc_normalize(child.path)] = nil
            child.path = op.dst .. child.path:sub(#op.src + 1)
            store.path_index[util.nfc_normalize(child.path)] = child.id
          end
        end
      end
      for _, entry in pairs(snapshot.entries) do
        if contains(op.src, entry.path) then
          entry.path = op.dst .. entry.path:sub(#op.src + 1)
        end
      end
    elseif op.type == "create" then
      local entry = entries_by_path[op.path]
      local parent = store:get_by_path(entry.parent_path) or root
      local id = store:add({
        name = entry.name,
        path = op.path,
        parent_id = parent.id,
        type = entry.is_dir and "directory" or "file",
        open = entry.is_dir,
        children_state = "loaded",
      })
      snapshot.entries[id] = { line = entry.line_nr, path = op.path }
      vim.api.nvim_buf_set_extmark(buffer.bufnr, buffer.painter.ns_ids, entry.line_nr, 0, {
        id = id,
        right_gravity = true,
        invalidate = true,
      })
    end
  end
  for _, node in pairs(store.nodes) do
    node._sorted_children_ids = nil
    node._sorted_children = nil
  end
  store:next_generation()
end

return M
