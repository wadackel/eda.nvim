local Store = require("eda.tree.store")

local T = MiniTest.new_set()

-- navigate() sets buffer.target_node_id to the node matching the given path.
-- The full navigate() is async (scan_ancestors + vim.schedule), but the core
-- logic is synchronous: store:get_by_path(path) → buffer.target_node_id = node.id.
-- These tests verify that core logic in isolation.

T["navigate core"] = MiniTest.new_set()

T["navigate core"]["sets target_node_id for existing file"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"
  store:add({ name = "foo.lua", path = "/project/foo.lua", type = "file", parent_id = root })

  -- Simulate what navigate()'s callback does
  local target_node_id = nil
  local path = "/project/foo.lua"
  local node = store:get_by_path(path)
  if node then
    target_node_id = node.id
  end

  MiniTest.expect.equality(target_node_id ~= nil, true)
  MiniTest.expect.equality(store:get(target_node_id).name, "foo.lua")
end

T["navigate core"]["sets target_node_id for nested file"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"
  local sub = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root })
  store:get(sub).children_state = "loaded"
  store:add({ name = "main.lua", path = "/project/src/main.lua", type = "file", parent_id = sub })

  local path = "/project/src/main.lua"
  local node = store:get_by_path(path)

  MiniTest.expect.equality(node ~= nil, true)
  MiniTest.expect.equality(node.name, "main.lua")
end

T["navigate core"]["returns nil for non-existent path"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"
  store:add({ name = "foo.lua", path = "/project/foo.lua", type = "file", parent_id = root })

  local node = store:get_by_path("/project/bar.lua")
  MiniTest.expect.equality(node, nil)
end

T["navigate core"]["does not set target_node_id when path not found"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"

  local target_node_id = nil
  local path = "/project/nonexistent.lua"
  local node = store:get_by_path(path)
  if node then
    target_node_id = node.id
  end

  MiniTest.expect.equality(target_node_id, nil)
end

return T
