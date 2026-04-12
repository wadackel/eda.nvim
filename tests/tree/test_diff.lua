local Diff = require("eda.tree.diff")
local Store = require("eda.tree.store")

local T = MiniTest.new_set()

local function make_snapshot(entries)
  return { entries = entries }
end

T["compute returns empty for no changes"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local file_id = store:add({ name = "foo.lua", path = "/project/foo.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [file_id] = { line = 0, path = "/project/foo.lua" },
  })

  local parsed = {
    { node_id = file_id, name = "foo.lua", full_path = "/project/foo.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 0)
end

T["compute detects CREATE for new lines"] = function()
  local store = Store.new()
  store:set_root("/project")

  local snapshot = make_snapshot({})
  local parsed = {
    { node_id = nil, name = "new.lua", full_path = "/project/new.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "create")
  MiniTest.expect.equality(ops[1].path, "/project/new.lua")
  MiniTest.expect.equality(ops[1].entry_type, "file")
end

T["compute detects CREATE directory"] = function()
  local store = Store.new()
  store:set_root("/project")

  local snapshot = make_snapshot({})
  local parsed = {
    { node_id = nil, name = "new_dir", full_path = "/project/new_dir", is_dir = true },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].entry_type, "directory")
end

T["compute detects DELETE"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local file_id = store:add({ name = "old.lua", path = "/project/old.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [file_id] = { line = 0, path = "/project/old.lua" },
  })

  -- Empty parsed = file was deleted from buffer
  local ops = Diff.compute({}, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "delete")
  MiniTest.expect.equality(ops[1].path, "/project/old.lua")
end

T["compute detects MOVE (rename)"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local file_id = store:add({ name = "old.lua", path = "/project/old.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [file_id] = { line = 0, path = "/project/old.lua" },
  })

  local parsed = {
    { node_id = file_id, name = "new.lua", full_path = "/project/new.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/old.lua")
  MiniTest.expect.equality(ops[1].dst, "/project/new.lua")
end

T["compute treats extmark-less line as CREATE even if name matches"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local file_id = store:add({ name = "foo.lua", path = "/project/foo.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [file_id] = { line = 0, path = "/project/foo.lua" },
  })

  -- Line with same name but no extmark = CREATE, not no-op
  local parsed = {
    { node_id = file_id, name = "foo.lua", full_path = "/project/foo.lua", is_dir = false },
    { node_id = nil, name = "foo.lua", full_path = "/project/foo.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "create")
end

T["compute orders MOVE before DELETE before CREATE"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local f1 = store:add({ name = "a.lua", path = "/project/a.lua", type = "file", parent_id = root })
  local f2 = store:add({ name = "b.lua", path = "/project/b.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [f1] = { line = 0, path = "/project/a.lua" },
    [f2] = { line = 1, path = "/project/b.lua" },
  })

  local parsed = {
    { node_id = f1, name = "a_renamed.lua", full_path = "/project/a_renamed.lua", is_dir = false },
    -- f2 deleted, new file created
    { node_id = nil, name = "c.lua", full_path = "/project/c.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  -- Should be: MOVE(a→a_renamed), DELETE(b), CREATE(c)
  MiniTest.expect.equality(#ops, 3)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[2].type, "delete")
  MiniTest.expect.equality(ops[3].type, "create")
end

T["compute moves children when expanded directory line is deleted via dd"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local dir_id = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root })
  local child1 = store:add({ name = "a.lua", path = "/project/src/a.lua", type = "file", parent_id = dir_id })
  local child2 = store:add({ name = "b.lua", path = "/project/src/b.lua", type = "file", parent_id = dir_id })

  local snapshot = make_snapshot({
    [dir_id] = { line = 0, path = "/project/src" },
    [child1] = { line = 1, path = "/project/src/a.lua" },
    [child2] = { line = 2, path = "/project/src/b.lua" },
  })

  -- User deleted the directory line; children remain and get re-parented to root
  local parsed = {
    { node_id = child1, name = "a.lua", full_path = "/project/a.lua", is_dir = false },
    { node_id = child2, name = "b.lua", full_path = "/project/b.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  -- MOVEs for children first, then DELETE for the directory
  MiniTest.expect.equality(#ops, 3)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/src/a.lua")
  MiniTest.expect.equality(ops[1].dst, "/project/a.lua")
  MiniTest.expect.equality(ops[2].type, "move")
  MiniTest.expect.equality(ops[2].src, "/project/src/b.lua")
  MiniTest.expect.equality(ops[2].dst, "/project/b.lua")
  MiniTest.expect.equality(ops[3].type, "delete")
  MiniTest.expect.equality(ops[3].path, "/project/src")
end

T["compute moves deeply nested children when ancestor directories are deleted"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local dir_id = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root })
  local sub_id = store:add({ name = "lib", path = "/project/src/lib", type = "directory", parent_id = dir_id })
  local file_id = store:add({ name = "c.lua", path = "/project/src/lib/c.lua", type = "file", parent_id = sub_id })

  local snapshot = make_snapshot({
    [dir_id] = { line = 0, path = "/project/src" },
    [sub_id] = { line = 1, path = "/project/src/lib" },
    [file_id] = { line = 2, path = "/project/src/lib/c.lua" },
  })

  -- User deleted directory and subdirectory lines; file re-parented to root
  local parsed = {
    { node_id = file_id, name = "c.lua", full_path = "/project/c.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  -- MOVE for file, then DELETEs for both directories (children-first: longer paths first)
  MiniTest.expect.equality(#ops, 3)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/src/lib/c.lua")
  MiniTest.expect.equality(ops[1].dst, "/project/c.lua")
  MiniTest.expect.equality(ops[2].type, "delete")
  MiniTest.expect.equality(ops[2].path, "/project/src/lib")
  MiniTest.expect.equality(ops[3].type, "delete")
  MiniTest.expect.equality(ops[3].path, "/project/src")
end

T["compute does not suppress unrelated MOVE when file is deleted"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local f1 = store:add({ name = "old.lua", path = "/project/old.lua", type = "file", parent_id = root })
  local f2 = store:add({ name = "keep.lua", path = "/project/keep.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [f1] = { line = 0, path = "/project/old.lua" },
    [f2] = { line = 1, path = "/project/keep.lua" },
  })

  -- f1 deleted, f2 renamed
  local parsed = {
    { node_id = f2, name = "renamed.lua", full_path = "/project/renamed.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 2)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/keep.lua")
  MiniTest.expect.equality(ops[2].type, "delete")
  MiniTest.expect.equality(ops[2].path, "/project/old.lua")
end

T["compute handles collapsed directory delete normally"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local dir_id = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root })

  local snapshot = make_snapshot({
    [dir_id] = { line = 0, path = "/project/src" },
  })

  -- Collapsed directory deleted (no children in snapshot)
  local ops = Diff.compute({}, snapshot, store)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "delete")
  MiniTest.expect.equality(ops[1].path, "/project/src")
  MiniTest.expect.equality(ops[1].entry_type, "directory")
end

T["compute respects path prefix boundary - /project/src delete does not suppress /project/srcobol MOVE"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local dir_id = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root })
  local other_id = store:add({ name = "main.lua", path = "/project/srcobol/main.lua", type = "file", parent_id = root })

  local snapshot = make_snapshot({
    [dir_id] = { line = 0, path = "/project/src" },
    [other_id] = { line = 1, path = "/project/srcobol/main.lua" },
  })

  -- src directory deleted; srcobol file renamed
  local parsed = {
    { node_id = other_id, name = "main.lua", full_path = "/project/srcobol_new/main.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  MiniTest.expect.equality(#ops, 2)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/srcobol/main.lua")
  MiniTest.expect.equality(ops[2].type, "delete")
  MiniTest.expect.equality(ops[2].path, "/project/src")
end

T["compute moves children to sibling directory when parent directory line deleted"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  local test_id = store:add({ name = "test", path = "/project/test", type = "directory", parent_id = root })
  local tests_id = store:add({ name = "tests", path = "/project/tests", type = "directory", parent_id = root })
  local t_child =
    store:add({ name = "foo_test.lua", path = "/project/test/foo_test.lua", type = "file", parent_id = test_id })
  local ts_child1 =
    store:add({ name = "bar_test.lua", path = "/project/tests/bar_test.lua", type = "file", parent_id = tests_id })
  local ts_child2 =
    store:add({ name = "baz_test.lua", path = "/project/tests/baz_test.lua", type = "file", parent_id = tests_id })

  local snapshot = make_snapshot({
    [test_id] = { line = 0, path = "/project/test" },
    [t_child] = { line = 1, path = "/project/test/foo_test.lua" },
    [tests_id] = { line = 2, path = "/project/tests" },
    [ts_child1] = { line = 3, path = "/project/tests/bar_test.lua" },
    [ts_child2] = { line = 4, path = "/project/tests/baz_test.lua" },
  })

  -- User deleted "tests/" directory line; its children visually fall under "test/"
  local parsed = {
    { node_id = test_id, name = "test", full_path = "/project/test", is_dir = true },
    { node_id = t_child, name = "foo_test.lua", full_path = "/project/test/foo_test.lua", is_dir = false },
    { node_id = ts_child1, name = "bar_test.lua", full_path = "/project/test/bar_test.lua", is_dir = false },
    { node_id = ts_child2, name = "baz_test.lua", full_path = "/project/test/baz_test.lua", is_dir = false },
  }

  local ops = Diff.compute(parsed, snapshot, store)
  -- 2 MOVEs (children of tests/ moved into test/), then 1 DELETE (tests/ directory)
  MiniTest.expect.equality(#ops, 3)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/tests/bar_test.lua")
  MiniTest.expect.equality(ops[1].dst, "/project/test/bar_test.lua")
  MiniTest.expect.equality(ops[2].type, "move")
  MiniTest.expect.equality(ops[2].src, "/project/tests/baz_test.lua")
  MiniTest.expect.equality(ops[2].dst, "/project/test/baz_test.lua")
  MiniTest.expect.equality(ops[3].type, "delete")
  MiniTest.expect.equality(ops[3].path, "/project/tests")
end

T["validate passes for valid operations"] = function()
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"

  local ops = {
    { type = "create", path = "/project/new.lua", entry_type = "file" },
  }
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, true)
end

T["validate passes for create with non-existent parent directory"] = function()
  local store = Store.new()
  store:set_root("/project")

  local ops = {
    { type = "create", path = "/project/foo/bar/file.md", entry_type = "file" },
  }
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, true)
  MiniTest.expect.equality(#result.errors, 0)
end

T["validate detects invalid move operation"] = function()
  local store = Store.new()
  store:set_root("/project")

  local ops = {
    { type = "move", path = "/project/new.lua" },
  }
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, false)
  MiniTest.expect.equality(#result.errors, 1)
  MiniTest.expect.equality(result.errors[1], "Move operation missing src or dst")
end

-- BUG-7: validate should reject move with same src and dst (no-op)
T["validate rejects move with same src and dst"] = function()
  local store = Store.new()
  store:set_root("/project")

  local ops = {
    { type = "move", src = "/project/file.lua", dst = "/project/file.lua", path = "/project/file.lua" },
  }
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, false)
  MiniTest.expect.equality(#result.errors, 1)
end

-- BUG-175: validate should reject duplicate destination paths (move+create conflict)
T["validate rejects duplicate destination from move and create"] = function()
  local store = Store.new()
  store:set_root("/project")

  local ops = {
    { type = "move", src = "/project/old.lua", dst = "/project/target.lua", path = "/project/target.lua" },
    { type = "create", path = "/project/target.lua", entry_type = "file" },
  }
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, false)
  MiniTest.expect.equality(#result.errors, 1)
  MiniTest.expect.equality(result.errors[1], "Duplicate destination path: /project/target.lua")
end

return T
