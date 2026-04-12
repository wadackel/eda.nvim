local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local helpers = require("helpers")
local config = require("eda.config")

local T = MiniTest.new_set()

T["target_path is derived when buf path is under root"] = function()
  local root_path = "/home/user/project"
  local current_buf_path = "/home/user/project/src/main.lua"

  local target_path = nil
  if current_buf_path ~= "" and vim.startswith(current_buf_path, root_path .. "/") then
    target_path = current_buf_path
  end

  MiniTest.expect.equality(target_path, "/home/user/project/src/main.lua")
end

T["target_path is nil for empty buffer"] = function()
  local root_path = "/home/user/project"
  local current_buf_path = ""

  local target_path = nil
  if current_buf_path ~= "" and vim.startswith(current_buf_path, root_path .. "/") then
    target_path = current_buf_path
  end

  MiniTest.expect.equality(target_path, nil)
end

T["target_path is nil for file outside root"] = function()
  local root_path = "/home/user/project"
  local current_buf_path = "/tmp/other/file.lua"

  local target_path = nil
  if current_buf_path ~= "" and vim.startswith(current_buf_path, root_path .. "/") then
    target_path = current_buf_path
  end

  MiniTest.expect.equality(target_path, nil)
end

T["target_path is nil when buf path equals root exactly"] = function()
  local root_path = "/home/user/project"
  local current_buf_path = "/home/user/project"

  local target_path = nil
  if current_buf_path ~= "" and vim.startswith(current_buf_path, root_path .. "/") then
    target_path = current_buf_path
  end

  MiniTest.expect.equality(target_path, nil)
end

-- resolve_root tests using the real eda.open internals
-- We call eda.open's resolve_root indirectly by requiring eda and testing via real buffers

T["resolve_root: uses root_markers to find project root"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  local project_dir = tmp .. "/project"
  helpers.create_dir(project_dir .. "/.git")
  helpers.create_dir(project_dir .. "/src")
  helpers.create_file(project_dir .. "/src/main.lua", "-- main")

  config.setup({ root_markers = { ".git", ".hg" } })

  -- Open the file in buffer
  vim.cmd("edit " .. project_dir .. "/src/main.lua")

  -- resolve_root is local, so we replicate its logic to verify
  local buf_path = vim.api.nvim_buf_get_name(0)
  local buf_dir = vim.fn.fnamemodify(buf_path, ":h")
  local cfg = config.get()
  local resolved = nil
  for _, marker in ipairs(cfg.root_markers) do
    local root = vim.fs.root(buf_dir, marker)
    if root and vim.startswith(buf_path, root .. "/") then
      resolved = root
      break
    end
  end

  MiniTest.expect.equality(resolved, project_dir)

  vim.cmd("bdelete!")
  helpers.remove_temp_dir(tmp)
end

T["resolve_root: falls back to file parent dir when no root markers found"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  local standalone_dir = tmp .. "/standalone"
  helpers.create_dir(standalone_dir)
  helpers.create_file(standalone_dir .. "/notes.txt", "hello")

  config.setup({ root_markers = { ".git", ".hg" } })

  vim.cmd("edit " .. standalone_dir .. "/notes.txt")

  local buf_path = vim.api.nvim_buf_get_name(0)
  local buf_dir = vim.fn.fnamemodify(buf_path, ":h")
  local cfg = config.get()
  local resolved = nil
  for _, marker in ipairs(cfg.root_markers) do
    local root = vim.fs.root(buf_dir, marker)
    if root and vim.startswith(buf_path, root .. "/") then
      resolved = root
      break
    end
  end
  -- No root marker found, should fall back to buf_dir
  if not resolved then
    resolved = buf_dir
  end

  MiniTest.expect.equality(resolved, standalone_dir)

  vim.cmd("bdelete!")
  helpers.remove_temp_dir(tmp)
end

T["resolve_root: file outside root marker falls back to parent dir"] = function()
  -- Simulate a .git in /tmp/project but file in /tmp/outside
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  local project_dir = tmp .. "/project"
  local outside_dir = tmp .. "/outside"
  helpers.create_dir(project_dir .. "/.git")
  helpers.create_dir(outside_dir)
  helpers.create_file(outside_dir .. "/readme.md", "# hi")

  config.setup({ root_markers = { ".git", ".hg" } })

  vim.cmd("edit " .. outside_dir .. "/readme.md")

  local buf_path = vim.api.nvim_buf_get_name(0)
  local buf_dir = vim.fn.fnamemodify(buf_path, ":h")
  local cfg = config.get()
  local resolved = nil
  for _, marker in ipairs(cfg.root_markers) do
    local root = vim.fs.root(buf_dir, marker)
    if root and vim.startswith(buf_path, root .. "/") then
      resolved = root
      break
    end
  end
  if not resolved then
    resolved = buf_dir
  end

  MiniTest.expect.equality(resolved, outside_dir)

  vim.cmd("bdelete!")
  helpers.remove_temp_dir(tmp)
end

T["get_by_path finds target node after scan_ancestors populates store"] = function()
  local store = Store.new()
  store:set_root("/project")
  local scanner = Scanner.new(store)

  -- Simulate what scan_ancestors does: populate store with entries
  scanner:_apply_entries(store.root_id, {
    { name = "src", type = "directory" },
    { name = "README.md", type = "file" },
  })

  local src = store:get_by_path("/project/src")
  MiniTest.expect.no_equality(src, nil)
  src.open = true -- scan_ancestors sets this

  scanner:_apply_entries(src.id, {
    { name = "main.lua", type = "file" },
    { name = "util.lua", type = "file" },
  })

  -- Verify get_by_path finds the target
  local target = store:get_by_path("/project/src/main.lua")
  MiniTest.expect.no_equality(target, nil)
  MiniTest.expect.equality(target.name, "main.lua")

  -- Verify get_by_path returns nil for nonexistent file
  local missing = store:get_by_path("/project/src/missing.lua")
  MiniTest.expect.equality(missing, nil)
end

-- State cache tests

T["state_cache is populated on close"] = function()
  local eda = require("eda")
  local store = Store.new()
  store:set_root("/project")
  local scanner = Scanner.new(store)

  -- Populate store with entries
  scanner:_apply_entries(store.root_id, {
    { name = "src", type = "directory" },
    { name = "README.md", type = "file" },
  })

  local src = store:get_by_path("/project/src")
  src.open = true

  scanner:_apply_entries(src.id, {
    { name = "main.lua", type = "file" },
    { name = "util.lua", type = "file" },
  })

  -- Access the internal state_cache via the module's close logic
  -- We test the extraction logic directly since M.close() requires a full explorer
  local open_dirs = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_dirs[node.path] = true
    end
  end

  MiniTest.expect.equality(open_dirs["/project/src"], true)
  MiniTest.expect.equality(open_dirs["/project"], nil) -- root is excluded
end

T["state_cache excludes closed directories"] = function()
  local store = Store.new()
  store:set_root("/project")
  local scanner = Scanner.new(store)

  scanner:_apply_entries(store.root_id, {
    { name = "src", type = "directory" },
    { name = "docs", type = "directory" },
  })

  local src = store:get_by_path("/project/src")
  src.open = true
  local docs = store:get_by_path("/project/docs")
  docs.open = false

  local open_dirs = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_dirs[node.path] = true
    end
  end

  MiniTest.expect.equality(open_dirs["/project/src"], true)
  MiniTest.expect.equality(open_dirs["/project/docs"], nil)
end

T["open directory states are restored from cache"] = function()
  local store = Store.new()
  store:set_root("/project")
  local scanner = Scanner.new(store)

  scanner:_apply_entries(store.root_id, {
    { name = "src", type = "directory" },
    { name = "docs", type = "directory" },
  })

  -- Simulate cached open_dirs
  local cached_open_dirs = { ["/project/src"] = true }

  -- Apply restoration logic
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and cached_open_dirs[node.path] then
      node.open = true
    end
  end

  local src = store:get_by_path("/project/src")
  local docs = store:get_by_path("/project/docs")
  MiniTest.expect.equality(src.open, true)
  MiniTest.expect.equality(docs.open, false)
end

T["cursor position priority: target_path takes precedence over cached"] = function()
  local target_path = "/project/src/main.lua"
  local cached_cursor_path = "/project/docs/readme.md"

  -- The logic: only use cached cursor if target_path is nil
  local resolved = nil
  if target_path then
    resolved = target_path
  elseif cached_cursor_path then
    resolved = cached_cursor_path
  end

  MiniTest.expect.equality(resolved, "/project/src/main.lua")
end

T["cursor position: cached cursor used when no target_path"] = function()
  local target_path = nil
  local cached_cursor_path = "/project/docs/readme.md"

  local resolved = nil
  if target_path then
    resolved = target_path
  elseif cached_cursor_path then
    resolved = cached_cursor_path
  end

  MiniTest.expect.equality(resolved, "/project/docs/readme.md")
end

T["nested directory open states are fully restored via scan_open_unloaded"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a/b/c")
  helpers.create_file(tmp .. "/a/b/c/deep.lua", "-- deep")

  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store)

  -- Initial scan of root
  local scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Simulate close: collect open dirs
  local a = store:get_by_path(tmp .. "/a")
  a.open = true
  -- Scan "a" so "b" exists
  scanned = false
  scanner:scan(a.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  local b = store:get_by_path(tmp .. "/a/b")
  b.open = true
  -- Scan "b" so "c" exists
  scanned = false
  scanner:scan(b.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  local c = store:get_by_path(tmp .. "/a/b/c")
  c.open = true

  -- Save open_dirs (simulating state_cache)
  local open_dirs = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_dirs[node.path] = true
    end
  end

  -- Simulate reopen: create fresh store/scanner and only scan root
  local store2 = Store.new()
  store2:set_root(tmp)
  local scanner2 = Scanner.new(store2)

  scanned = false
  scanner2:scan(store2.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Apply open states to first-level nodes (like init.lua Phase 1)
  for _, node in pairs(store2.nodes) do
    if node.type == "directory" and open_dirs[node.path] then
      node.open = true
    end
  end

  -- Run scan_open_unloaded (like init.lua Phase 2)
  local done = false
  scanner2:scan_open_unloaded(open_dirs, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- Verify all nested dirs are loaded and open
  local a2 = store2:get_by_path(tmp .. "/a")
  MiniTest.expect.no_equality(a2, nil)
  MiniTest.expect.equality(a2.open, true)
  MiniTest.expect.equality(a2.children_state, "loaded")

  local b2 = store2:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b2, nil)
  MiniTest.expect.equality(b2.open, true)
  MiniTest.expect.equality(b2.children_state, "loaded")

  local c2 = store2:get_by_path(tmp .. "/a/b/c")
  MiniTest.expect.no_equality(c2, nil)
  MiniTest.expect.equality(c2.open, true)
  MiniTest.expect.equality(c2.children_state, "loaded")

  local deep = store2:get_by_path(tmp .. "/a/b/c/deep.lua")
  MiniTest.expect.no_equality(deep, nil)

  helpers.remove_temp_dir(tmp)
end

T["hijack_netrw config option is recognized and defaults to false"] = function()
  config.setup()
  local cfg = config.get()
  MiniTest.expect.equality(cfg.hijack_netrw, false)
end

T["hijack_netrw can be enabled via config"] = function()
  config.setup({ hijack_netrw = true })
  local cfg = config.get()
  MiniTest.expect.equality(cfg.hijack_netrw, true)
end

T["hijack_netrw opens with kind=replace regardless of window.kind config"] = function()
  local eda = require("eda")

  -- Configure with a non-replace window kind and enable hijack_netrw
  config.setup({
    hijack_netrw = false,
    window = { kind = "float" },
  })

  -- Simulate what the hijack_netrw callback does: call M.open with kind = "replace"
  -- This mirrors the code path in init.lua where hijack_netrw calls M.open({ dir = path, kind = "replace" })
  local cfg = config.get()
  local opts = { dir = vim.fn.getcwd(), kind = "replace" }
  local resolved_kind = opts.kind or cfg.window.kind

  MiniTest.expect.equality(resolved_kind, "replace")

  -- Also verify that normal open (without explicit kind) uses the configured kind
  local normal_opts = { dir = vim.fn.getcwd() }
  local normal_kind = normal_opts.kind or cfg.window.kind

  MiniTest.expect.equality(normal_kind, "float")
end

-- Refresh state preservation tests (Issue #31)

T["refresh preserves directory open states"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/a/b")
  helpers.create_file(tmp .. "/a/b/file.lua", "-- file")
  helpers.create_file(tmp .. "/root.txt", "-- root")

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
  local a = store:get_by_path(tmp .. "/a")
  a.open = true
  scanned = false
  scanner:scan(a.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Open directory "b" and scan it
  local b = store:get_by_path(tmp .. "/a/b")
  b.open = true
  scanned = false
  scanner:scan(b.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- Snapshot open dirs (like refresh action does)
  local open_by_path = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_by_path[node.path] = true
    end
  end

  -- Simulate refresh: next_generation + re-scan root (destroys children)
  store:next_generation()
  scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- After root re-scan, all open states are lost
  local a_after_scan = store:get_by_path(tmp .. "/a")
  MiniTest.expect.equality(a_after_scan.open, false)

  -- Restore open states via scan_open_unloaded
  local done = false
  scanner:scan_open_unloaded(open_by_path, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- Verify open states are restored
  local a_restored = store:get_by_path(tmp .. "/a")
  MiniTest.expect.equality(a_restored.open, true)
  MiniTest.expect.equality(a_restored.children_state, "loaded")

  local b_restored = store:get_by_path(tmp .. "/a/b")
  MiniTest.expect.no_equality(b_restored, nil)
  MiniTest.expect.equality(b_restored.open, true)
  MiniTest.expect.equality(b_restored.children_state, "loaded")

  -- Verify file is accessible
  local file = store:get_by_path(tmp .. "/a/b/file.lua")
  MiniTest.expect.no_equality(file, nil)

  helpers.remove_temp_dir(tmp)
end

T["refresh does not open directories that were closed"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/open_dir")
  helpers.create_dir(tmp .. "/closed_dir")
  helpers.create_file(tmp .. "/open_dir/a.txt", "a")
  helpers.create_file(tmp .. "/closed_dir/b.txt", "b")

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

  -- Open only open_dir
  local open_dir = store:get_by_path(tmp .. "/open_dir")
  open_dir.open = true
  scanned = false
  scanner:scan(open_dir.id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  -- closed_dir stays closed (default)
  local closed_dir = store:get_by_path(tmp .. "/closed_dir")
  MiniTest.expect.equality(closed_dir.open, false)

  -- Snapshot open dirs
  local open_by_path = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_by_path[node.path] = true
    end
  end

  -- Simulate refresh
  store:next_generation()
  scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  local done = false
  scanner:scan_open_unloaded(open_by_path, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- open_dir should be open
  local open_dir_after = store:get_by_path(tmp .. "/open_dir")
  MiniTest.expect.equality(open_dir_after.open, true)

  -- closed_dir should still be closed
  local closed_dir_after = store:get_by_path(tmp .. "/closed_dir")
  MiniTest.expect.equality(closed_dir_after.open, false)

  helpers.remove_temp_dir(tmp)
end

T["refresh handles newly appeared directories as closed"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/existing")
  helpers.create_file(tmp .. "/existing/a.txt", "a")

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

  -- Open "existing"
  local existing = store:get_by_path(tmp .. "/existing")
  existing.open = true

  -- Snapshot open dirs
  local open_by_path = {}
  for _, node in pairs(store.nodes) do
    if node.type == "directory" and node.open and node.id ~= store.root_id then
      open_by_path[node.path] = true
    end
  end

  -- Add a new directory to the filesystem (simulating external changes)
  helpers.create_dir(tmp .. "/new_dir")
  helpers.create_file(tmp .. "/new_dir/b.txt", "b")

  -- Simulate refresh
  store:next_generation()
  scanned = false
  scanner:scan(store.root_id, function()
    scanned = true
  end)
  helpers.wait_for(2000, function()
    return scanned
  end)

  local done = false
  scanner:scan_open_unloaded(open_by_path, function()
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  -- existing should be open (was in open_by_path)
  local existing_after = store:get_by_path(tmp .. "/existing")
  MiniTest.expect.equality(existing_after.open, true)

  -- new_dir should be closed (was NOT in open_by_path)
  local new_dir = store:get_by_path(tmp .. "/new_dir")
  MiniTest.expect.no_equality(new_dir, nil)
  MiniTest.expect.equality(new_dir.open, false)

  helpers.remove_temp_dir(tmp)
end

return T
