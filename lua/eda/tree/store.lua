local Node = require("eda.tree.node")
local util = require("eda.util")

---@class eda.Store
---@field nodes table<integer, eda.TreeNode>
---@field next_id integer
---@field root_id integer
---@field path_index table<string, integer>
---@field generation integer
local Store = {}
Store.__index = Store

---Create a new empty store.
---@return eda.Store
function Store.new()
  return setmetatable({
    nodes = {},
    next_id = 1,
    root_id = 0,
    path_index = {},
    generation = 0,
  }, Store)
end

---Add a node to the store.
---@param fields table Partial node fields (id will be assigned)
---@return integer id The assigned node ID
function Store:add(fields)
  local id = self.next_id
  self.next_id = self.next_id + 1
  fields.id = id
  local node = Node.create(fields)
  self.nodes[id] = node
  self.path_index[util.nfc_normalize(node.path)] = id

  -- Add to parent's children_ids
  if node.parent_id and self.nodes[node.parent_id] then
    local parent = self.nodes[node.parent_id]
    if parent.children_ids == nil then
      parent.children_ids = {}
    end
    table.insert(parent.children_ids, id)
    parent._sorted_children_ids = nil
    parent._sorted_children = nil
  end

  return id
end

---Get a node by ID.
---@param id integer
---@return eda.TreeNode?
function Store:get(id)
  return self.nodes[id]
end

---Get a node by path.
---@param path string
---@return eda.TreeNode?
function Store:get_by_path(path)
  local id = self.path_index[util.nfc_normalize(path)]
  if id then
    return self.nodes[id]
  end
  return nil
end

---Resolve a real path through symlink nodes in the store.
---Finds the symlink whose link_target is the longest prefix of path,
---then rewrites path by replacing the link_target prefix with the symlink's own path.
---@param path string Absolute real path (e.g., from vim.uv.fs_realpath)
---@return string? resolved_path The rewritten store-compatible path, or nil if no match
function Store:resolve_symlink_path(path)
  local normalized = util.nfc_normalize(path)
  local best_node = nil
  local best_len = 0
  for _, node in pairs(self.nodes) do
    if node.link_target then
      local lt = util.nfc_normalize(node.link_target)
      local lt_slash = lt .. "/"
      if normalized == lt or normalized:sub(1, #lt_slash) == lt_slash then
        if #lt > best_len then
          best_len = #lt
          best_node = node
        end
      end
    end
  end
  if not best_node then
    return nil
  end
  if normalized == util.nfc_normalize(best_node.link_target) then
    return best_node.path
  end
  return best_node.path .. normalized:sub(best_len + 1)
end

---Remove a node and all its descendants from the store.
---@param id integer
function Store:remove(id)
  local node = self.nodes[id]
  if not node then
    return
  end

  -- Recursively remove all descendants first
  if node.children_ids then
    local children = node.children_ids --[[@as integer[] ]]
    for _, child_id in ipairs(vim.deepcopy(children)) do
      self:remove(child_id)
    end
  end

  -- Remove from parent's children_ids
  if node.parent_id and self.nodes[node.parent_id] then
    local parent = self.nodes[node.parent_id]
    if parent.children_ids then
      for i, child_id in ipairs(parent.children_ids) do
        if child_id == id then
          table.remove(parent.children_ids, i)
          break
        end
      end
      parent._sorted_children_ids = nil
      parent._sorted_children = nil
    end
  end

  self.path_index[util.nfc_normalize(node.path)] = nil
  self.nodes[id] = nil
end

local function purge(store, id)
  local node = store.nodes[id]
  if not node then
    return
  end
  for _, child_id in ipairs(node.children_ids or {}) do
    purge(store, child_id)
  end
  store.path_index[util.nfc_normalize(node.path)] = nil
  store.nodes[id] = nil
end

---@param parent_id integer
function Store:remove_children(parent_id)
  local parent = self.nodes[parent_id]
  if not parent then
    return
  end
  for _, child_id in ipairs(parent.children_ids or {}) do
    purge(self, child_id)
  end
  parent.children_ids = {}
  parent._sorted_children_ids = nil
  parent._sorted_children = nil
end

---@param parent_id integer
---@param entries table[]
---@return boolean changed
function Store:reconcile_children(parent_id, entries)
  local parent = self.nodes[parent_id]
  if not parent then
    return false
  end
  local remaining, by_path = {}, {}
  for _, id in ipairs(parent.children_ids or {}) do
    local child = self.nodes[id]
    if child then
      remaining[id] = true
      by_path[util.nfc_normalize(child.path)] = child
    end
  end
  local children, changed = {}, false
  for _, fields in ipairs(entries) do
    local previous = by_path[util.nfc_normalize(fields.path)]
    if previous then
      remaining[previous.id] = nil
    end
    local unchanged = previous
      and previous.name == fields.name
      and previous.path == fields.path
      and previous.type == fields.type
      and previous.link_target == fields.link_target
      and previous.link_broken == (fields.link_broken or false)
      and previous.error == fields.error
    if unchanged then
      children[#children + 1] = previous.id
    else
      if previous then
        -- Reusing a followed symlink's children would keep entries from its former target.
        purge(self, previous.id)
      end
      fields.parent_id = parent_id
      local id = self:add(fields)
      self.nodes[id]._marked = fields._marked
      children[#children + 1] = id
      changed = true
    end
  end
  for id in pairs(remaining) do
    purge(self, id)
    changed = true
  end
  if changed or parent.children_ids == nil then
    parent.children_ids = children
    parent._sorted_children_ids = nil
    parent._sorted_children = nil
  end
  parent.children_state = "loaded"
  if changed then
    self:next_generation()
  end
  return changed
end

local sort_key_cache = {}

---Natural sort key: pad numeric segments with zeros.
---Results are memoized since file names are reused across renders.
---@param name string
---@return string
local function natural_sort_key(name)
  local cached = sort_key_cache[name]
  if cached then
    return cached
  end
  local key = name:lower():gsub("%d+", function(n)
    return string.format("%010d", tonumber(n))
  end)
  sort_key_cache[name] = key
  return key
end

---Get sorted children of a node.
---Directories first, then natural sort by name.
---Results are cached per node and invalidated on add/remove.
---@param id integer
---@return eda.TreeNode[]
function Store:children(id)
  local node = self.nodes[id]
  if not node or not node.children_ids then
    return {}
  end

  if node._sorted_children then
    return node._sorted_children
  end

  if node._sorted_children_ids then
    local children = {}
    for _, child_id in ipairs(node._sorted_children_ids) do
      local child = self.nodes[child_id]
      if child then
        children[#children + 1] = child
      end
    end
    node._sorted_children = children
    return children
  end

  local children = {}
  for _, child_id in ipairs(node.children_ids) do
    local child = self.nodes[child_id]
    if child then
      table.insert(children, child)
    end
  end

  table.sort(children, function(a, b)
    local a_dir = Node.is_dir(a)
    local b_dir = Node.is_dir(b)
    if a_dir ~= b_dir then
      return a_dir
    end
    return natural_sort_key(a.name) < natural_sort_key(b.name)
  end)

  local sorted_ids = {}
  for _, c in ipairs(children) do
    table.insert(sorted_ids, c.id)
  end
  node._sorted_children_ids = sorted_ids
  node._sorted_children = children

  return children
end

---Get ancestors from root to the given node.
---@param id integer
---@return eda.TreeNode[]
function Store:ancestors(id)
  local result = {}
  local node = self.nodes[id]
  while node do
    table.insert(result, 1, node)
    if node.parent_id then
      node = self.nodes[node.parent_id]
    else
      break
    end
  end
  return result
end

---Set the root node of the store.
---@param path string Absolute path for the root directory
---@return integer root_id
function Store:set_root(path)
  local name = vim.fn.fnamemodify(path, ":t")
  if name == "" then
    name = path
  end
  local id = self:add({
    name = name,
    path = path,
    type = "directory",
    open = true,
  })
  self.root_id = id
  return id
end

---Increment and return the generation counter.
---@return integer
function Store:next_generation()
  self.generation = self.generation + 1
  return self.generation
end

---Natural sort comparator key.
---Exposed so other modules (e.g. `eda.tree.ascii`) can share the same name ordering
---as the explorer's visible children sort, avoiding drift between rendered views.
Store.natural_sort_key = natural_sort_key

return Store
