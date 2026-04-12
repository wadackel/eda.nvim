local Node = require("eda.tree.node")

local T = MiniTest.new_set()

T["create"] = MiniTest.new_set()

T["create"]["fills defaults"] = function()
  local n = Node.create({ id = 1, name = "foo", path = "/foo" })
  MiniTest.expect.equality(n.id, 1)
  MiniTest.expect.equality(n.name, "foo")
  MiniTest.expect.equality(n.path, "/foo")
  MiniTest.expect.equality(n.type, "file")
  MiniTest.expect.equality(n.parent_id, nil)
  MiniTest.expect.equality(n.children_ids, nil)
  MiniTest.expect.equality(n.children_state, "unloaded")
  MiniTest.expect.equality(n.open, false)
  MiniTest.expect.equality(n.link_target, nil)
  MiniTest.expect.equality(n.link_broken, false)
  MiniTest.expect.equality(n.error, nil)
end

T["create"]["respects overrides"] = function()
  local n = Node.create({
    id = 2,
    name = "src",
    path = "/src",
    type = "directory",
    open = true,
    children_ids = {},
    children_state = "loaded",
  })
  MiniTest.expect.equality(n.type, "directory")
  MiniTest.expect.equality(n.open, true)
  MiniTest.expect.equality(n.children_state, "loaded")
end

T["is_dir"] = MiniTest.new_set()

T["is_dir"]["returns true for directory"] = function()
  local n = Node.create({ id = 1, name = "d", path = "/d", type = "directory" })
  MiniTest.expect.equality(Node.is_dir(n), true)
end

T["is_dir"]["returns false for file"] = function()
  local n = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  MiniTest.expect.equality(Node.is_dir(n), false)
end

T["is_file"] = MiniTest.new_set()

T["is_file"]["returns true for file"] = function()
  local n = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  MiniTest.expect.equality(Node.is_file(n), true)
end

T["is_file"]["returns false for directory"] = function()
  local n = Node.create({ id = 1, name = "d", path = "/d", type = "directory" })
  MiniTest.expect.equality(Node.is_file(n), false)
end

T["is_link"] = MiniTest.new_set()

T["is_link"]["returns true for link"] = function()
  local n = Node.create({ id = 1, name = "l", path = "/l", type = "link" })
  MiniTest.expect.equality(Node.is_link(n), true)
end

T["is_link"]["returns false for file"] = function()
  local n = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  MiniTest.expect.equality(Node.is_link(n), false)
end

return T
