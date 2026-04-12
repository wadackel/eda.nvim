local Store = require("eda.tree.store")

local T = MiniTest.new_set()

T["add/get"] = MiniTest.new_set()

T["add/get"]["adds node and retrieves by id"] = function()
  local store = Store.new()
  local id = store:add({ name = "foo.lua", path = "/foo.lua", type = "file" })
  local node = store:get(id)
  MiniTest.expect.equality(node.name, "foo.lua")
  MiniTest.expect.equality(node.id, id)
end

T["add/get"]["assigns monotonic ids"] = function()
  local store = Store.new()
  local id1 = store:add({ name = "a", path = "/a" })
  local id2 = store:add({ name = "b", path = "/b" })
  MiniTest.expect.equality(id2 > id1, true)
end

T["add/get"]["updates path_index"] = function()
  local store = Store.new()
  store:add({ name = "foo", path = "/foo" })
  local node = store:get_by_path("/foo")
  MiniTest.expect.equality(node.name, "foo")
end

T["add/get"]["adds to parent children_ids"] = function()
  local store = Store.new()
  local parent_id = store:add({ name = "src", path = "/src", type = "directory" })
  store:add({ name = "a.lua", path = "/src/a.lua", parent_id = parent_id })
  local parent = store:get(parent_id)
  MiniTest.expect.equality(#parent.children_ids, 1)
end

T["remove"] = MiniTest.new_set()

T["remove"]["removes from nodes and path_index"] = function()
  local store = Store.new()
  local id = store:add({ name = "foo", path = "/foo" })
  store:remove(id)
  MiniTest.expect.equality(store:get(id), nil)
  MiniTest.expect.equality(store:get_by_path("/foo"), nil)
end

T["remove"]["removes from parent children_ids"] = function()
  local store = Store.new()
  local pid = store:add({ name = "src", path = "/src", type = "directory" })
  local cid = store:add({ name = "a.lua", path = "/src/a.lua", parent_id = pid })
  store:remove(cid)
  local parent = store:get(pid)
  MiniTest.expect.equality(#parent.children_ids, 0)
end

T["children"] = MiniTest.new_set()

T["children"]["returns empty for node without children"] = function()
  local store = Store.new()
  local id = store:add({ name = "f", path = "/f", type = "file" })
  MiniTest.expect.equality(#store:children(id), 0)
end

T["children"]["sorts directories first"] = function()
  local store = Store.new()
  local pid = store:add({ name = "root", path = "/root", type = "directory" })
  store:add({ name = "b.lua", path = "/root/b.lua", type = "file", parent_id = pid })
  store:add({ name = "src", path = "/root/src", type = "directory", parent_id = pid })
  local children = store:children(pid)
  MiniTest.expect.equality(#children, 2)
  MiniTest.expect.equality(children[1].name, "src")
  MiniTest.expect.equality(children[2].name, "b.lua")
end

T["children"]["natural sorts numeric names"] = function()
  local store = Store.new()
  local pid = store:add({ name = "root", path = "/root", type = "directory" })
  store:add({ name = "file10.lua", path = "/root/file10.lua", type = "file", parent_id = pid })
  store:add({ name = "file2.lua", path = "/root/file2.lua", type = "file", parent_id = pid })
  store:add({ name = "file1.lua", path = "/root/file1.lua", type = "file", parent_id = pid })
  local children = store:children(pid)
  MiniTest.expect.equality(#children, 3)
  MiniTest.expect.equality(children[1].name, "file1.lua")
  MiniTest.expect.equality(children[2].name, "file2.lua")
  MiniTest.expect.equality(children[3].name, "file10.lua")
end

T["children"]["invalidates cache on add"] = function()
  local store = Store.new()
  local pid = store:add({ name = "root", path = "/root", type = "directory" })
  store:add({ name = "a.lua", path = "/root/a.lua", type = "file", parent_id = pid })
  local children1 = store:children(pid)
  MiniTest.expect.equality(#children1, 1)
  -- Add another child; cache should be invalidated
  store:add({ name = "b.lua", path = "/root/b.lua", type = "file", parent_id = pid })
  local children2 = store:children(pid)
  MiniTest.expect.equality(#children2, 2)
  MiniTest.expect.equality(children2[1].name, "a.lua")
  MiniTest.expect.equality(children2[2].name, "b.lua")
end

T["children"]["invalidates cache on remove"] = function()
  local store = Store.new()
  local pid = store:add({ name = "root", path = "/root", type = "directory" })
  store:add({ name = "a.lua", path = "/root/a.lua", type = "file", parent_id = pid })
  local cid = store:add({ name = "b.lua", path = "/root/b.lua", type = "file", parent_id = pid })
  local children1 = store:children(pid)
  MiniTest.expect.equality(#children1, 2)
  -- Remove a child; cache should be invalidated
  store:remove(cid)
  local children2 = store:children(pid)
  MiniTest.expect.equality(#children2, 1)
  MiniTest.expect.equality(children2[1].name, "a.lua")
end

T["ancestors"] = MiniTest.new_set()

T["ancestors"]["returns root to node path"] = function()
  local store = Store.new()
  local root = store:add({ name = "root", path = "/root", type = "directory" })
  local src = store:add({ name = "src", path = "/root/src", type = "directory", parent_id = root })
  local file = store:add({ name = "a.lua", path = "/root/src/a.lua", type = "file", parent_id = src })
  local anc = store:ancestors(file)
  MiniTest.expect.equality(#anc, 3)
  MiniTest.expect.equality(anc[1].id, root)
  MiniTest.expect.equality(anc[2].id, src)
  MiniTest.expect.equality(anc[3].id, file)
end

T["set_root"] = MiniTest.new_set()

T["set_root"]["creates root node"] = function()
  local store = Store.new()
  local id = store:set_root("/project")
  MiniTest.expect.equality(store.root_id, id)
  local root = store:get(id)
  MiniTest.expect.equality(root.type, "directory")
  MiniTest.expect.equality(root.open, true)
  MiniTest.expect.equality(root.path, "/project")
end

T["remove_children"] = MiniTest.new_set()

T["remove_children"]["removes all children and descendants"] = function()
  local store = Store.new()
  local pid = store:add({ name = "root", path = "/root", type = "directory" })
  local c1 = store:add({ name = "src", path = "/root/src", type = "directory", parent_id = pid })
  local gc = store:add({ name = "a.lua", path = "/root/src/a.lua", type = "file", parent_id = c1 })
  local c2 = store:add({ name = "b.lua", path = "/root/b.lua", type = "file", parent_id = pid })
  store:remove_children(pid)
  -- All descendants removed
  MiniTest.expect.equality(store:get(c1), nil)
  MiniTest.expect.equality(store:get(gc), nil)
  MiniTest.expect.equality(store:get(c2), nil)
  -- Path index cleared
  MiniTest.expect.equality(store:get_by_path("/root/src"), nil)
  MiniTest.expect.equality(store:get_by_path("/root/src/a.lua"), nil)
  MiniTest.expect.equality(store:get_by_path("/root/b.lua"), nil)
  -- Parent still exists with empty children_ids
  local parent = store:get(pid)
  MiniTest.expect.equality(parent.name, "root")
  MiniTest.expect.equality(#parent.children_ids, 0)
end

T["remove_children"]["handles node without children"] = function()
  local store = Store.new()
  local id = store:add({ name = "f", path = "/f", type = "file" })
  -- Should not error
  store:remove_children(id)
  MiniTest.expect.equality(store:get(id).name, "f")
end

T["remove_children"]["handles nonexistent node"] = function()
  local store = Store.new()
  -- Should not error
  store:remove_children(999)
end

T["resolve_symlink_path"] = MiniTest.new_set()

T["resolve_symlink_path"]["resolves path under symlink link_target"] = function()
  local store = Store.new()
  local root = store:add({ name = "project", path = "/project", type = "directory" })
  store:add({ name = "node_modules", path = "/project/node_modules", type = "directory", parent_id = root })
  store:add({
    name = "react",
    path = "/project/node_modules/react",
    type = "link",
    parent_id = root,
    link_target = "/project/node_modules/.pnpm/react@18.2.0/node_modules/react",
  })
  local resolved = store:resolve_symlink_path("/project/node_modules/.pnpm/react@18.2.0/node_modules/react/index.js")
  MiniTest.expect.equality(resolved, "/project/node_modules/react/index.js")
end

T["resolve_symlink_path"]["returns symlink path on exact match"] = function()
  local store = Store.new()
  local root = store:add({ name = "project", path = "/project", type = "directory" })
  store:add({
    name = "react",
    path = "/project/node_modules/react",
    type = "link",
    parent_id = root,
    link_target = "/real/path/react",
  })
  local resolved = store:resolve_symlink_path("/real/path/react")
  MiniTest.expect.equality(resolved, "/project/node_modules/react")
end

T["resolve_symlink_path"]["picks longest matching link_target"] = function()
  local store = Store.new()
  local root = store:add({ name = "project", path = "/project", type = "directory" })
  store:add({
    name = "nm",
    path = "/project/nm",
    type = "link",
    parent_id = root,
    link_target = "/real",
  })
  store:add({
    name = "react",
    path = "/project/react",
    type = "link",
    parent_id = root,
    link_target = "/real/deep/react",
  })
  local resolved = store:resolve_symlink_path("/real/deep/react/index.js")
  MiniTest.expect.equality(resolved, "/project/react/index.js")
end

T["resolve_symlink_path"]["returns nil when no symlink matches"] = function()
  local store = Store.new()
  store:add({ name = "project", path = "/project", type = "directory" })
  local resolved = store:resolve_symlink_path("/unrelated/path/file.lua")
  MiniTest.expect.equality(resolved, nil)
end

T["next_generation"] = MiniTest.new_set()

T["next_generation"]["increments monotonically"] = function()
  local store = Store.new()
  local g1 = store:next_generation()
  local g2 = store:next_generation()
  MiniTest.expect.equality(g1, 1)
  MiniTest.expect.equality(g2, 2)
end

return T
