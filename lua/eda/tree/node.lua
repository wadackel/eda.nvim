local M = {}

---@class eda.TreeNode
---@field id integer Unique, monotonically increasing
---@field name string Basename (e.g. "init.lua")
---@field path string Absolute normalized path
---@field type "file"|"directory"|"link"
---@field parent_id integer? nil for root
---@field children_ids integer[]? Ordered, nil when unloaded
---@field children_state "unloaded"|"loading"|"loaded"
---@field open boolean Directory expanded or not
---@field link_target string? Symlink target path
---@field link_broken boolean Symlink target does not exist
---@field error string? "permission_denied", "symlink_cycle", etc.
---@field _sorted_children_ids integer[]? Cached sorted children (invalidated on add/remove)
---@field _sorted_children eda.TreeNode[]?
---@field _marked boolean?

-- Fields that have non-nil defaults
local non_nil_defaults = {
  id = 0,
  name = "",
  path = "",
  type = "file",
  children_state = "unloaded",
  open = false,
  link_broken = false,
}

-- Fields that default to nil (must be listed explicitly since pairs skips nil values)
local nil_fields = { "parent_id", "children_ids", "link_target", "error" }

---Create a new TreeNode with defaults filled in.
---@param fields table Partial node fields
---@return eda.TreeNode
function M.create(fields)
  local node = {}
  for k, v in pairs(non_nil_defaults) do
    node[k] = fields[k] ~= nil and fields[k] or v
  end
  for _, k in ipairs(nil_fields) do
    node[k] = fields[k]
  end
  return node
end

---Check if a node represents a directory.
---@param node eda.TreeNode
---@return boolean
function M.is_dir(node)
  return node.type == "directory"
end

---Check if a node represents a file.
---@param node eda.TreeNode
---@return boolean
function M.is_file(node)
  return node.type == "file"
end

---Check if a node represents a symlink.
---@param node eda.TreeNode
---@return boolean
function M.is_link(node)
  return node.type == "link"
end

return M
