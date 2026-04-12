local git = require("eda.git")
local helpers = require("helpers")

local T = MiniTest.new_set()

T["module loads"] = function()
  MiniTest.expect.equality(type(git.status), "function")
  MiniTest.expect.equality(type(git.get_cached), "function")
  MiniTest.expect.equality(type(git.invalidate), "function")
end

T["get_cached returns nil for non-git directory"] = function()
  local result = git.get_cached("/tmp/nonexistent_dir_xyz")
  MiniTest.expect.equality(result, nil)
end

T["invalidate does not error on non-git directory"] = function()
  git.invalidate("/tmp/nonexistent_dir_xyz")
  MiniTest.expect.equality(true, true)
end

T["status calls callback with nil for non-git directory"] = function()
  local tmpdir = helpers.create_temp_dir()

  -- git.status uses vim.system + vim.schedule, but for non-git dirs
  -- it calls cb(nil) synchronously via the early return
  local called = false
  local result = "not_nil"
  git.status(tmpdir, function(status)
    result = status
    called = true
  end)

  -- For non-git directory, cb is called synchronously
  MiniTest.expect.equality(called, true)
  MiniTest.expect.equality(result, nil)

  helpers.remove_temp_dir(tmpdir)
end

-- Test parse_status indirectly by running git status and checking cached results.
-- Since git.status uses vim.system + vim.schedule which don't pump in mini.test
-- child processes, we test the parse logic by verifying git porcelain output format
-- expectations directly.

T["git porcelain status format for untracked files"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/new_file.txt", "hello")

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Untracked files show as "?? filename"
  MiniTest.expect.equality(result:find("%?%? new_file%.txt") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

T["git porcelain status format for added files"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/added.txt", "hello")
  vim.fn.system({ "git", "-C", tmpdir, "add", "added.txt" })

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Added files show as "A  filename"
  MiniTest.expect.equality(result:find("A  added%.txt") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

T["git porcelain status format for modified files"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/mod.txt", "original")
  vim.fn.system({ "git", "-C", tmpdir, "add", "mod.txt" })
  vim.fn.system({ "git", "-C", tmpdir, "commit", "-m", "init" })
  helpers.create_file(tmpdir .. "/mod.txt", "modified")

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Modified files show as " M filename"
  MiniTest.expect.equality(result:find(" M mod%.txt") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

T["git porcelain status format for deleted files"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/del.txt", "content")
  vim.fn.system({ "git", "-C", tmpdir, "add", "del.txt" })
  vim.fn.system({ "git", "-C", tmpdir, "commit", "-m", "init" })
  vim.fn.delete(tmpdir .. "/del.txt")

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Deleted files show as " D filename"
  MiniTest.expect.equality(result:find(" D del%.txt") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

T["git porcelain status format for renamed files"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/old_name.txt", "content")
  vim.fn.system({ "git", "-C", tmpdir, "add", "old_name.txt" })
  vim.fn.system({ "git", "-C", tmpdir, "commit", "-m", "init" })
  vim.fn.system({ "git", "-C", tmpdir, "mv", "old_name.txt", "new_name.txt" })

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Renamed files show as "R  old -> new"
  MiniTest.expect.equality(result:find("R") ~= nil, true)
  MiniTest.expect.equality(result:find("new_name%.txt") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

T["parse_status: ignored + untracked mixed dir gets untracked status"] = function()
  local result = git._parse_status("!! dir/ignored.txt\n?? dir/new.txt", "/root")
  MiniTest.expect.equality(result["/root/dir"], "?")
  MiniTest.expect.equality(result["/root/dir/ignored.txt"], "!")
  MiniTest.expect.equality(result["/root/dir/new.txt"], "?")
end

T["parse_status: ignored + modified mixed dir gets modified status"] = function()
  local result = git._parse_status("!! dir/.env\n M dir/main.lua", "/root")
  MiniTest.expect.equality(result["/root/dir"], "M")
end

T["parse_status: multiple statuses dir gets highest priority"] = function()
  local result = git._parse_status("?? dir/new.txt\n M dir/changed.lua\nUU dir/conflict.lua", "/root")
  MiniTest.expect.equality(result["/root/dir"], "U")
end

T["parse_status: deep nesting propagates to all ancestors"] = function()
  local result = git._parse_status(" M a/b/c/file.lua", "/root")
  MiniTest.expect.equality(result["/root/a/b/c"], "M")
  MiniTest.expect.equality(result["/root/a/b"], "M")
  MiniTest.expect.equality(result["/root/a"], "M")
end

T["parse_status: explicit ignored dir after child does not downgrade"] = function()
  local result = git._parse_status("?? vendor/used.txt\n!! vendor/", "/root")
  MiniTest.expect.equality(result["/root/vendor"], "?")
end

T["parse_status: ignored file does not propagate to parent"] = function()
  local result = git._parse_status("!! dir/secret.txt", "/root")
  MiniTest.expect.equality(result["/root/dir/secret.txt"], "!")
  MiniTest.expect.equality(result["/root/dir"], nil)
end

T["parse_status: ignored deep nesting does not propagate to ancestors"] = function()
  local result = git._parse_status("!! a/b/c/ignored.log", "/root")
  MiniTest.expect.equality(result["/root/a/b/c/ignored.log"], "!")
  MiniTest.expect.equality(result["/root/a/b/c"], nil)
  MiniTest.expect.equality(result["/root/a/b"], nil)
  MiniTest.expect.equality(result["/root/a"], nil)
end

T["git porcelain status for nested files in subdirectories"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_dir(tmpdir .. "/src/lib")
  helpers.create_file(tmpdir .. "/src/lib/mod.lua", "hello")

  local result = vim.fn.system({ "git", "-C", tmpdir, "status", "--porcelain", "-uall" })
  -- Nested untracked files show the full relative path
  MiniTest.expect.equality(result:find("src/lib/mod%.lua") ~= nil, true)

  helpers.remove_temp_dir(tmpdir)
end

-- is_gitignored tests

T["is_gitignored returns true for file inside ignored directory"] = function()
  local status = { ["/root/target"] = "!" }
  MiniTest.expect.equality(git.is_gitignored(status, "/root/target/classes/Main.class"), true)
end

T["is_gitignored returns true for deeply nested file"] = function()
  local status = { ["/root/target"] = "!" }
  MiniTest.expect.equality(git.is_gitignored(status, "/root/target/a/b/c/d.txt"), true)
end

T["is_gitignored returns false for file not inside ignored directory"] = function()
  local status = { ["/root/target"] = "!" }
  MiniTest.expect.equality(git.is_gitignored(status, "/root/src/main.lua"), false)
end

T["is_gitignored returns false for empty git_status"] = function()
  MiniTest.expect.equality(git.is_gitignored({}, "/root/src/main.lua"), false)
end

T["is_gitignored returns false for direct ignored file"] = function()
  local status = { ["/root/secret.txt"] = "!" }
  MiniTest.expect.equality(git.is_gitignored(status, "/root/secret.txt"), false)
end

T["is_gitignored returns true for subdirectory of ignored directory"] = function()
  local status = { ["/root/node_modules"] = "!" }
  MiniTest.expect.equality(git.is_gitignored(status, "/root/node_modules/lodash"), true)
end

-- is_changed_status tests (exposed as _is_changed_status for internal testing)

T["_is_changed_status returns true for M/A/D/R/C/?/U"] = function()
  MiniTest.expect.equality(git._is_changed_status("M"), true)
  MiniTest.expect.equality(git._is_changed_status("A"), true)
  MiniTest.expect.equality(git._is_changed_status("D"), true)
  MiniTest.expect.equality(git._is_changed_status("R"), true)
  MiniTest.expect.equality(git._is_changed_status("C"), true)
  MiniTest.expect.equality(git._is_changed_status("?"), true)
  MiniTest.expect.equality(git._is_changed_status("U"), true)
end

T["_is_changed_status returns false for ! and space"] = function()
  MiniTest.expect.equality(git._is_changed_status("!"), false)
  MiniTest.expect.equality(git._is_changed_status(" "), false)
end

-- parse_status with reported_out tests

T["parse_status with reported_out collects direct changed file paths"] = function()
  local reported = {}
  git._parse_status(" M a/b/file.lua\n?? new.txt", "/root", reported)
  MiniTest.expect.equality(reported["/root/a/b/file.lua"], true)
  MiniTest.expect.equality(reported["/root/new.txt"], true)
  -- dir propagation should NOT appear in reported set
  MiniTest.expect.equality(reported["/root/a"], nil)
  MiniTest.expect.equality(reported["/root/a/b"], nil)
end

T["parse_status with reported_out excludes ignored entries"] = function()
  local reported = {}
  git._parse_status("!! dir/secret.txt\n M dir/code.lua", "/root", reported)
  MiniTest.expect.equality(reported["/root/dir/secret.txt"], nil)
  MiniTest.expect.equality(reported["/root/dir/code.lua"], true)
end

T["parse_status with reported_out excludes ignored directory entries (--ignored=matching)"] = function()
  local reported = {}
  git._parse_status("!! node_modules/\n?? new.txt", "/root", reported)
  MiniTest.expect.equality(reported["/root/node_modules"], nil)
  MiniTest.expect.equality(reported["/root/new.txt"], true)
end

T["parse_status with reported_out stores renamed file's new path"] = function()
  local reported = {}
  git._parse_status("R  old.txt -> new.txt", "/root", reported)
  MiniTest.expect.equality(reported["/root/new.txt"], true)
  MiniTest.expect.equality(reported["/root/old.txt"], nil)
end

-- get_reported_changes / get_status_ready tests

T["get_reported_changes returns nil for non-git directory"] = function()
  local result = git.get_reported_changes("/tmp/nonexistent_dir_xyz_reported")
  MiniTest.expect.equality(result, nil)
end

T["get_status_ready returns no_repo for non-git directory after status call"] = function()
  local tmpdir = helpers.create_temp_dir()
  git.status(tmpdir, function(_) end)
  MiniTest.expect.equality(git.get_status_ready(tmpdir), "no_repo")
  git.invalidate(tmpdir)
  helpers.remove_temp_dir(tmpdir)
end

T["get_status_ready and get_reported_changes return ready state after git status completes"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/tracked.txt", "original")
  vim.fn.system({ "git", "-C", tmpdir, "add", "tracked.txt" })
  vim.fn.system({ "git", "-C", tmpdir, "commit", "-m", "init" })
  helpers.create_file(tmpdir .. "/tracked.txt", "modified")
  helpers.create_file(tmpdir .. "/new.txt", "untracked content")

  -- macOS tempname may return /var/folders while git reports /private/var/folders
  local git_root = vim.fn.system({ "git", "-C", tmpdir, "rev-parse", "--show-toplevel" })
  git_root = git_root:gsub("\n$", "")

  local done = false
  git.status(tmpdir, function(_)
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(git.get_status_ready(tmpdir), "ready")

  local reported = git.get_reported_changes(tmpdir)
  MiniTest.expect.equality(type(reported), "table")
  MiniTest.expect.equality(reported[git_root .. "/tracked.txt"], true)
  MiniTest.expect.equality(reported[git_root .. "/new.txt"], true)

  git.invalidate(tmpdir)
  helpers.remove_temp_dir(tmpdir)
end

T["get_cached return shape unchanged (backward compat)"] = function()
  local tmpdir = helpers.create_temp_dir()
  vim.fn.system({ "git", "-C", tmpdir, "init" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", tmpdir, "config", "user.name", "Test" })
  helpers.create_file(tmpdir .. "/file.txt", "hello")

  local git_root = vim.fn.system({ "git", "-C", tmpdir, "rev-parse", "--show-toplevel" })
  git_root = git_root:gsub("\n$", "")

  local done = false
  git.status(tmpdir, function(_)
    done = true
  end)
  helpers.wait_for(5000, function()
    return done
  end)

  local cached = git.get_cached(tmpdir)
  MiniTest.expect.equality(type(cached), "table")
  -- Existing callers expect path→code map
  MiniTest.expect.equality(cached[git_root .. "/file.txt"], "?")

  git.invalidate(tmpdir)
  helpers.remove_temp_dir(tmpdir)
end

return T
