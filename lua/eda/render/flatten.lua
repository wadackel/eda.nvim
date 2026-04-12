local Node = require("eda.tree.node")

local M = {}

---@class eda.FlatLine
---@field node_id integer
---@field depth integer
---@field node eda.TreeNode

---@class eda.FlattenOpts
---@field filter? fun(node: eda.TreeNode): boolean  -- visibility: whether to include node in result
---@field should_descend? fun(node: eda.TreeNode): boolean  -- traversal: whether to descend into a loaded dir (defaults to node.open)

---Flatten the tree into a list of FlatLine entries for rendering.
---Performs DFS traversal. Evaluation order per child: filter → append to result →
---should_descend → recurse. `children_state == "loaded"` is always required for descent.
---@param store eda.Store
---@param root_id integer
---@param opts? eda.FlattenOpts
---@return eda.FlatLine[]
function M.flatten(store, root_id, opts)
  local result = {}
  local filter = opts and opts.filter
  local should_descend = opts and opts.should_descend

  local function walk(node_id, depth)
    local children = store:children(node_id)
    for _, child in ipairs(children) do
      if not filter or filter(child) then
        table.insert(result, {
          node_id = child.id,
          depth = depth,
          node = child,
        })
        if Node.is_dir(child) and child.children_state == "loaded" then
          local descend
          if should_descend then
            descend = should_descend(child)
          else
            descend = child.open
          end
          if descend then
            walk(child.id, depth + 1)
          end
        end
      end
    end
  end

  walk(root_id, 0)
  return result
end

return M
