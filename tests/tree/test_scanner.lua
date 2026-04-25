local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local helpers = require("helpers")

local T = MiniTest.new_set()

T["new creates scanner"] = function()
  local store = Store.new()
  local scanner = Scanner.new(store)
  MiniTest.expect.equality(type(scanner), "table")
  MiniTest.expect.equality(scanner.store, store)
end

T["scan rejects non-directory"] = function()
  local store = Store.new()
  local id = store:add({ name = "f", path = "/f", type = "file" })
  local scanner = Scanner.new(store)
  local err_msg
  scanner:scan(id, function(err)
    err_msg = err
  end)
  MiniTest.expect.equality(err_msg, "not a directory")
end

T["scan coalesces callback when already scanning"] = function()
  local store = Store.new()
  local id = store:add({ name = "d", path = "/nonexistent_dir_for_test", type = "directory" })
  local scanner = Scanner.new(store)
  scanner._scanning[id] = true
  local fired = false
  scanner:scan(id, function()
    fired = true
  end)
  -- Callback must NOT fire synchronously when a scan is already in flight.
  -- It is queued in the waiter list and would fire when the original scan settles.
  MiniTest.expect.equality(fired, false)
  MiniTest.expect.equality(type(scanner._waiters), "table")
  MiniTest.expect.equality(#scanner._waiters[id], 1)
end

-- SC-W1: two parallel scan calls on the same node both observe completion.
T["SC-W1 two parallel scans both observe completion"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/dir")
  helpers.create_file(tmp .. "/dir/a.txt", "a")
  helpers.create_file(tmp .. "/dir/b.txt", "b")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root first so the dir node exists in the store
  local root_done = false
  scanner:scan(store.root_id, function()
    root_done = true
  end)
  helpers.wait_for(2000, function()
    return root_done
  end)

  local dir_node = store:get_by_path(tmp .. "/dir")
  MiniTest.expect.no_equality(dir_node, nil)

  -- Two parallel scan calls before settle. The second is queued as a waiter and
  -- must observe completion after the first scan settles.
  local first_fired = false
  local second_fired = false
  scanner:scan(dir_node.id, function()
    first_fired = true
  end)
  scanner:scan(dir_node.id, function()
    second_fired = true
  end)

  helpers.wait_for(5000, function()
    return first_fired and second_fired
  end)

  MiniTest.expect.equality(first_fired, true)
  MiniTest.expect.equality(second_fired, true)
  MiniTest.expect.equality(dir_node.children_state, "loaded")

  helpers.remove_temp_dir(tmp)
end

T["_apply_entries populates store"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_apply")
  local scanner = Scanner.new(store)

  local entries = {
    { name = "src", type = "directory" },
    { name = "README.md", type = "file" },
    { name = "util.lua", type = "file" },
  }

  scanner:_apply_entries(root_id, entries)

  local root = store:get(root_id)
  MiniTest.expect.equality(root.children_state, "loaded")

  local children = store:children(root_id)
  MiniTest.expect.equality(#children, 3)
  -- directories first, then natural sort
  MiniTest.expect.equality(children[1].name, "src")
  MiniTest.expect.equality(children[1].type, "directory")
  MiniTest.expect.equality(children[2].name, "README.md")
  MiniTest.expect.equality(children[3].name, "util.lua")
end

T["_apply_entries replaces old children"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_replace")
  local scanner = Scanner.new(store)

  -- First scan
  scanner:_apply_entries(root_id, {
    { name = "old.lua", type = "file" },
  })
  MiniTest.expect.equality(#store:children(root_id), 1)
  MiniTest.expect.equality(store:children(root_id)[1].name, "old.lua")

  -- Second scan replaces
  scanner:_apply_entries(root_id, {
    { name = "new.lua", type = "file" },
    { name = "other.lua", type = "file" },
  })
  MiniTest.expect.equality(#store:children(root_id), 2)
  MiniTest.expect.equality(store:get_by_path("/tmp/test_replace/old.lua"), nil)
end

T["scan_open_unloaded iteratively scans 3-level nested directories"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a/b/c")
  helpers.create_file(tmp .. "/a/b/c/file.txt", "hello")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root only
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Set up open_dirs for all 3 levels
  local open_dirs = {
    [tmp .. "/a"] = true,
    [tmp .. "/a/b"] = true,
    [tmp .. "/a/b/c"] = true,
  }

  -- Mark directory "a" as open (simulating cached state)
  local a_node = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a_node, nil)
  a_node.open = true

  -- Run scan_open_unloaded
  local done = false
  scanner:scan_open_unloaded(open_dirs, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- Verify all levels are loaded and open
  local a = store:get_by_path(tmp .. "/a")
  MiniTest.expect.equality(a.open, true)
  MiniTest.expect.equality(a.children_state, "loaded")

  local b = store:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b, nil)
  MiniTest.expect.equality(b.open, true)
  MiniTest.expect.equality(b.children_state, "loaded")

  local c = store:get_by_path(tmp .. "/a/b/c")
  MiniTest.expect.no_equality(c, nil)
  MiniTest.expect.equality(c.open, true)
  MiniTest.expect.equality(c.children_state, "loaded")

  local file = store:get_by_path(tmp .. "/a/b/c/file.txt")
  MiniTest.expect.no_equality(file, nil)

  helpers.remove_temp_dir(tmp)
end

T["scan_open_unloaded handles non-existent paths in open_dirs"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/real_dir")
  helpers.create_file(tmp .. "/real_dir/file.txt", "content")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- open_dirs with paths that don't exist on disk
  local open_dirs = {
    [tmp .. "/nonexistent"] = true,
    [tmp .. "/also_missing"] = true,
  }

  -- Should terminate safely without errors
  local done = false
  scanner:scan_open_unloaded(open_dirs, function()
    done = true
  end)
  helpers.wait_for(2000, function()
    return done
  end)

  MiniTest.expect.equality(done, true)

  helpers.remove_temp_dir(tmp)
end

T["rescan_preserving_state restores open directories"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a/b")
  helpers.create_file(tmp .. "/a/b/file.txt", "hello")
  helpers.create_dir(tmp .. "/c")
  helpers.create_file(tmp .. "/c/other.txt", "world")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Open directory "a" and scan it
  local a_node = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a_node, nil)
  a_node.open = true

  scanned = false
  scanner:scan(a_node.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Open directory "a/b" and scan it
  local b_node = store:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b_node, nil)
  b_node.open = true

  scanned = false
  scanner:scan(b_node.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Open directory "c" and scan it
  local c_node = store:get_by_path(tmp .. "/c")
  MiniTest.expect.no_equality(c_node, nil)
  c_node.open = true

  scanned = false
  scanner:scan(c_node.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Verify all dirs are open before rescan
  MiniTest.expect.equality(store:get_by_path(tmp .. "/a").open, true)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/a/b").open, true)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/c").open, true)

  -- Now rescan_preserving_state should restore open states
  local done = false
  scanner:rescan_preserving_state(store.root_id, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- Verify directories are still open after rescan
  local a_after = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a_after, nil)
  MiniTest.expect.equality(a_after.open, true)
  MiniTest.expect.equality(a_after.children_state, "loaded")

  local b_after = store:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b_after, nil)
  MiniTest.expect.equality(b_after.open, true)
  MiniTest.expect.equality(b_after.children_state, "loaded")

  local c_after = store:get_by_path(tmp .. "/c")
  MiniTest.expect.no_equality(c_after, nil)
  MiniTest.expect.equality(c_after.open, true)
  MiniTest.expect.equality(c_after.children_state, "loaded")

  -- Verify files are still accessible
  MiniTest.expect.no_equality(store:get_by_path(tmp .. "/a/b/file.txt"), nil)
  MiniTest.expect.no_equality(store:get_by_path(tmp .. "/c/other.txt"), nil)

  helpers.remove_temp_dir(tmp)
end

T["rescan_preserving_state works with no open dirs"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a")
  helpers.create_file(tmp .. "/a/file.txt", "hello")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- No directories are open -- rescan should not crash
  local done = false
  scanner:rescan_preserving_state(store.root_id, function()
    done = true
  end)
  helpers.wait_for(2000, function()
    return done
  end)

  MiniTest.expect.equality(done, true)

  -- Root children should still be present
  local a_node = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a_node, nil)
  MiniTest.expect.equality(a_node.children_state, "unloaded")

  helpers.remove_temp_dir(tmp)
end

T["scan_open_unloaded respects global fd semaphore limit"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  -- Create 100+ directories to exceed the default limit of 32
  for i = 1, 100 do
    helpers.create_dir(tmp .. "/dir_" .. string.format("%03d", i))
    helpers.create_file(tmp .. "/dir_" .. string.format("%03d", i) .. "/file.txt", "content")
  end

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root first
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(5000, function()
    return scanned
  end)

  -- Build open_dirs for all 100 directories
  local open_dirs = {}
  for i = 1, 100 do
    open_dirs[tmp .. "/dir_" .. string.format("%03d", i)] = true
  end

  -- Track peak _active_fds during scan
  local peak_fds = 0
  local orig_do_scan_io = Scanner._do_scan_io
  Scanner._do_scan_io = function(self, ...)
    if self._active_fds > peak_fds then
      peak_fds = self._active_fds
    end
    return orig_do_scan_io(self, ...)
  end

  local done = false
  scanner:scan_open_unloaded(open_dirs, function()
    done = true
  end)
  helpers.wait_for(10000, function()
    return done
  end)

  -- Restore original method
  Scanner._do_scan_io = orig_do_scan_io

  -- Peak should not exceed the limit
  MiniTest.expect.equality(peak_fds <= scanner._max_concurrent_fds, true)
  -- All fds should be released
  MiniTest.expect.equality(scanner._active_fds, 0)
  -- Pending queue should be empty
  MiniTest.expect.equality(#scanner._pending_scans, 0)

  helpers.remove_temp_dir(tmp)
end

T["scan_recursive respects global fd semaphore limit"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  -- Create a wide 3-level tree
  for i = 1, 10 do
    for j = 1, 10 do
      helpers.create_dir(tmp .. "/d" .. i .. "/d" .. j)
      helpers.create_file(tmp .. "/d" .. i .. "/d" .. j .. "/f.txt", "x")
    end
  end

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Track peak _active_fds
  local peak_fds = 0
  local orig_do_scan_io = Scanner._do_scan_io
  Scanner._do_scan_io = function(self, ...)
    if self._active_fds > peak_fds then
      peak_fds = self._active_fds
    end
    return orig_do_scan_io(self, ...)
  end

  local done = false
  scanner:scan_recursive(store.root_id, 5, function()
    done = true
  end)
  helpers.wait_for(10000, function()
    return done
  end)

  Scanner._do_scan_io = orig_do_scan_io

  MiniTest.expect.equality(peak_fds <= scanner._max_concurrent_fds, true)
  MiniTest.expect.equality(scanner._active_fds, 0)

  helpers.remove_temp_dir(tmp)
end

T["scan fd semaphore recovers from opendir errors"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  -- Create a directory that we'll make unreadable
  helpers.create_dir(tmp .. "/no_access")
  helpers.create_dir(tmp .. "/normal")
  helpers.create_file(tmp .. "/normal/file.txt", "ok")

  -- Remove read permission
  vim.fn.setfperm(tmp .. "/no_access", "rwx------")
  vim.fn.setfperm(tmp .. "/no_access", "-wx------")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Scan the unreadable directory
  local no_access = store:get_by_path(tmp .. "/no_access")
  MiniTest.expect.no_equality(no_access, nil)

  local err_done = false
  scanner:scan(no_access.id, function()
    err_done = true
  end)
  helpers.wait_for(2000, function()
    return err_done
  end)

  -- After error, _active_fds should return to 0
  MiniTest.expect.equality(scanner._active_fds, 0)
  -- Pending queue should be empty
  MiniTest.expect.equality(#scanner._pending_scans, 0)

  helpers.remove_temp_dir(tmp)
end

T["scan_recursive expands multi-level directories with closed nodes"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a/b/c")
  helpers.create_file(tmp .. "/a/b/c/file.txt", "hello")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Scan root only
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Verify "a" exists but is NOT open
  local a_node = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a_node, nil)
  MiniTest.expect.equality(a_node.open, false)

  -- Run scan_recursive from root with max_depth=5, all nodes are closed
  local done = false
  scanner:scan_recursive(store.root_id, 5, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- Verify all levels have children_state == "loaded"
  local a = store:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a, nil)
  MiniTest.expect.equality(a.children_state, "loaded")

  local b = store:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b, nil)
  MiniTest.expect.equality(b.children_state, "loaded")

  local c = store:get_by_path(tmp .. "/a/b/c")
  MiniTest.expect.no_equality(c, nil)
  MiniTest.expect.equality(c.children_state, "loaded")

  local file = store:get_by_path(tmp .. "/a/b/c/file.txt")
  MiniTest.expect.no_equality(file, nil)

  helpers.remove_temp_dir(tmp)
end

T["_apply_entries filters by static ignore_patterns"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_ignore")
  local scanner = Scanner.new(store, { ignore_patterns = { "%.log$", "^%.git$" } })

  local entries = {
    { name = "app.lua", type = "file" },
    { name = "debug.log", type = "file" },
    { name = ".git", type = "directory" },
    { name = "src", type = "directory" },
  }

  scanner:_apply_entries(root_id, entries)

  local children = store:children(root_id)
  MiniTest.expect.equality(#children, 2)
  MiniTest.expect.equality(children[1].name, "src")
  MiniTest.expect.equality(children[2].name, "app.lua")
end

T["_apply_entries filters by function ignore_patterns"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_ignore_fn")
  local received_root_path
  local scanner = Scanner.new(store, {
    ignore_patterns = function(root_path)
      received_root_path = root_path
      return { "%.tmp$" }
    end,
  })

  local entries = {
    { name = "keep.lua", type = "file" },
    { name = "remove.tmp", type = "file" },
  }

  scanner:_apply_entries(root_id, entries)

  MiniTest.expect.equality(received_root_path, "/tmp/test_ignore_fn")
  local children = store:children(root_id)
  MiniTest.expect.equality(#children, 1)
  MiniTest.expect.equality(children[1].name, "keep.lua")
end

T["_apply_entries empty ignore_patterns does not filter"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_empty_ignore")
  local scanner = Scanner.new(store, { ignore_patterns = {} })

  local entries = {
    { name = "a.lua", type = "file" },
    { name = "b.lua", type = "file" },
  }

  scanner:_apply_entries(root_id, entries)

  local children = store:children(root_id)
  MiniTest.expect.equality(#children, 2)
end

T["_apply_entries function returning nil treated as empty"] = function()
  local store = Store.new()
  local root_id = store:set_root("/tmp/test_nil_ignore")
  local scanner = Scanner.new(store, {
    ignore_patterns = function()
      return nil
    end,
  })

  local entries = {
    { name = "a.lua", type = "file" },
    { name = "b.lua", type = "file" },
  }

  scanner:_apply_entries(root_id, entries)

  local children = store:children(root_id)
  MiniTest.expect.equality(#children, 2)
end

return T
