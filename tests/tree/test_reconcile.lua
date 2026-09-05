local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local T = MiniTest.new_set()

local function fixture()
  local store = Store.new()
  store:set_root("/tree")
  local scanner = Scanner.new(store)
  scanner:_apply_entries(store.root_id, { { name = "dir", type = "directory" }, { name = "file", type = "file" } })
  local dir = store:get_by_path("/tree/dir")
  dir.open, dir._marked = true, true
  scanner:_apply_entries(dir.id, { { name = "inside", type = "file" } })
  return store, scanner, dir
end

T["unchanged entries retain objects IDs descendants and sorting caches"] = function()
  local store, scanner, dir = fixture()
  local children = store:children(store.root_id)
  local inside = store:get_by_path("/tree/dir/inside")
  local next_id = store.next_id
  scanner:_apply_entries(store.root_id, { { name = "file", type = "file" }, { name = "dir", type = "directory" } })
  MiniTest.expect.equality(store:get(dir.id) == dir, true)
  MiniTest.expect.equality(store:get(inside.id) == inside, true)
  MiniTest.expect.equality(store:children(store.root_id) == children, true)
  MiniTest.expect.equality(store.next_id, next_id)
  MiniTest.expect.equality({ dir.open, dir._marked, dir.children_state }, { true, true, "loaded" })
end

T["adding and removing siblings preserves the surviving subtree"] = function()
  local store, scanner, dir = fixture()
  local removed = store:get_by_path("/tree/file")
  scanner:_apply_entries(store.root_id, { { name = "dir", type = "directory" }, { name = "new", type = "file" } })
  MiniTest.expect.equality(store:get(dir.id) == dir, true)
  MiniTest.expect.equality(store:get_by_path("/tree/dir/inside") ~= nil, true)
  MiniTest.expect.equality(store:get(removed.id), nil)
  MiniTest.expect.equality(store:get_by_path("/tree/file"), nil)
  MiniTest.expect.equality(store:get_by_path("/tree/new") ~= nil, true)
  MiniTest.expect.equality(#store:children(store.root_id), 2)
end

T["replacing a directory purges its descendants"] = function()
  local store, scanner, dir = fixture()
  scanner:_apply_entries(store.root_id, { { name = "dir", type = "file" } })
  local replacement = store:get_by_path("/tree/dir")
  MiniTest.expect.equality(replacement.type, "file")
  MiniTest.expect.equality(replacement.id ~= dir.id, true)
  MiniTest.expect.equality(store:get_by_path("/tree/dir/inside"), nil)
  MiniTest.expect.equality(store:get(dir.id), nil)
end

T["changing a followed symlink target drops its loaded subtree"] = function()
  local store, _, dir = fixture()
  dir.link_target = "/old"
  store:reconcile_children(store.root_id, {
    { name = "dir", path = "/tree/dir", type = "directory", link_target = "/new" },
  })
  MiniTest.expect.equality(store:get_by_path("/tree/dir").id ~= dir.id, true)
  MiniTest.expect.equality(store:get_by_path("/tree/dir/inside"), nil)
end

return T
