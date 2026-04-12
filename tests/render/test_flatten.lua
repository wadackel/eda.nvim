local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")

local T = MiniTest.new_set()

local function build_tree()
  local store = Store.new()
  local root = store:set_root("/project")
  -- Add children: src/ (directory), README.md (file)
  local src = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root, open = true })
  store:add({ name = "init.lua", path = "/project/src/init.lua", type = "file", parent_id = src })
  store:add({ name = "util.lua", path = "/project/src/util.lua", type = "file", parent_id = src })
  store:add({ name = "README.md", path = "/project/README.md", type = "file", parent_id = root })

  -- Mark src as loaded
  local src_node = store:get(src)
  src_node.children_state = "loaded"

  -- Mark root as loaded
  local root_node = store:get(root)
  root_node.children_state = "loaded"

  return store, root
end

T["flatten returns correct DFS order"] = function()
  local store, root = build_tree()
  local lines = Flatten.flatten(store, root)

  -- Expected order: src/ (depth 0), init.lua (depth 1), util.lua (depth 1), README.md (depth 0)
  MiniTest.expect.equality(#lines, 4)
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[1].depth, 0)
  MiniTest.expect.equality(lines[2].node.name, "init.lua")
  MiniTest.expect.equality(lines[2].depth, 1)
  MiniTest.expect.equality(lines[3].node.name, "util.lua")
  MiniTest.expect.equality(lines[3].depth, 1)
  MiniTest.expect.equality(lines[4].node.name, "README.md")
  MiniTest.expect.equality(lines[4].depth, 0)
end

T["flatten skips collapsed directories"] = function()
  local store, root = build_tree()
  -- Collapse src
  local src = store:get_by_path("/project/src")
  src.open = false

  local lines = Flatten.flatten(store, root)
  MiniTest.expect.equality(#lines, 2) -- src (collapsed) + README.md
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[2].node.name, "README.md")
end

T["flatten skips unloaded directories"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root, open = true })
  -- src is unloaded (default), root is loaded
  local root_node = store:get(root)
  root_node.children_state = "loaded"

  local lines = Flatten.flatten(store, root)
  MiniTest.expect.equality(#lines, 1) -- only src, not its children
  MiniTest.expect.equality(lines[1].node.name, "src")
end

T["flatten with filter skips non-matching nodes"] = function()
  local store, root = build_tree()
  local lines = Flatten.flatten(store, root, {
    filter = function(node)
      return node.name ~= "util.lua"
    end,
  })

  MiniTest.expect.equality(#lines, 3)
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[2].node.name, "init.lua")
  MiniTest.expect.equality(lines[3].node.name, "README.md")
end

T["flatten with filter skips directory and all descendants"] = function()
  local store, root = build_tree()
  local lines = Flatten.flatten(store, root, {
    filter = function(node)
      return node.name ~= "src"
    end,
  })

  -- src is filtered out, so its children (init.lua, util.lua) are also excluded
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1].node.name, "README.md")
end

T["flatten with nil opts preserves existing behavior"] = function()
  local store, root = build_tree()
  local lines = Flatten.flatten(store, root, nil)

  MiniTest.expect.equality(#lines, 4)
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[2].node.name, "init.lua")
  MiniTest.expect.equality(lines[3].node.name, "util.lua")
  MiniTest.expect.equality(lines[4].node.name, "README.md")
end

T["flatten returns empty for empty root"] = function()
  local store = Store.new()
  local root = store:set_root("/empty")
  local root_node = store:get(root)
  root_node.children_state = "loaded"
  root_node.children_ids = {}

  local lines = Flatten.flatten(store, root)
  MiniTest.expect.equality(#lines, 0)
end

-- should_descend option tests (Task 2)

T["should_descend=true descends closed but loaded dir"] = function()
  local store, root = build_tree()
  -- Collapse src
  local src = store:get_by_path("/project/src")
  src.open = false

  local lines = Flatten.flatten(store, root, {
    should_descend = function(node)
      return node.name == "src" or node.open
    end,
  })

  -- src is closed but should_descend forces traversal
  MiniTest.expect.equality(#lines, 4)
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[2].node.name, "init.lua")
  MiniTest.expect.equality(lines[3].node.name, "util.lua")
  MiniTest.expect.equality(lines[4].node.name, "README.md")
end

T["should_descend does not descend into unloaded dir"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root, open = false })
  -- src is unloaded (default), root is loaded
  local root_node = store:get(root)
  root_node.children_state = "loaded"

  local lines = Flatten.flatten(store, root, {
    should_descend = function(_)
      return true -- try to descend unconditionally
    end,
  })

  -- src is unloaded, should_descend does not override the loaded guard
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1].node.name, "src")
end

T["should_descend nil falls back to node.open"] = function()
  local store, root = build_tree()
  -- src.open = true (default from build_tree)
  local lines = Flatten.flatten(store, root, {
    should_descend = nil,
  })
  MiniTest.expect.equality(#lines, 4) -- same as no opts
end

T["filter and should_descend are orthogonal: filter removes node but descend still runs on others"] = function()
  -- Build tree: project/ with src/init.lua, src/util.lua, README.md
  -- Filter: hide README.md. should_descend: force descent into src (even if closed).
  local store, root = build_tree()
  local src = store:get_by_path("/project/src")
  src.open = false -- close src

  local lines = Flatten.flatten(store, root, {
    filter = function(node)
      return node.name ~= "README.md"
    end,
    should_descend = function(node)
      return node.name == "src"
    end,
  })

  -- Expected: src, init.lua, util.lua (README.md filtered out)
  MiniTest.expect.equality(#lines, 3)
  MiniTest.expect.equality(lines[1].node.name, "src")
  MiniTest.expect.equality(lines[2].node.name, "init.lua")
  MiniTest.expect.equality(lines[3].node.name, "util.lua")
end

T["filter removes dir, should_descend cannot resurrect it (filter runs first)"] = function()
  local store, root = build_tree()
  local lines = Flatten.flatten(store, root, {
    filter = function(node)
      return node.name ~= "src"
    end,
    should_descend = function(node)
      return node.name == "src" or node.open
    end,
  })

  -- src is filtered out, so its children are also excluded (filter is evaluated before should_descend)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1].node.name, "README.md")
end

return T
