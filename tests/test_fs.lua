local Fs = require("eda.fs")
local helpers = require("helpers")

local T = MiniTest.new_set()

local function create_and_wait(path, is_dir)
  local done, result = false, nil
  Fs.create(path, is_dir, function(err)
    result = err
    done = true
  end)
  helpers.wait_for(3000, function()
    return done
  end)
  return result
end

T["create rejects an existing file without changing its contents"] = function()
  local dir = helpers.create_temp_dir()
  local path = dir .. "/keep.txt"
  helpers.create_file(path, "keep this content")
  MiniTest.expect.equality(type(create_and_wait(path, false)), "string")
  MiniTest.expect.equality(vim.fn.readfile(path), { "keep this content" })
  helpers.remove_temp_dir(dir)
end

T["create rejects an existing directory"] = function()
  local dir = helpers.create_temp_dir()
  MiniTest.expect.equality(type(create_and_wait(dir, true)), "string")
  MiniTest.expect.equality(vim.fn.isdirectory(dir), 1)
  helpers.remove_temp_dir(dir)
end

T["create rejects valid and broken symlink destinations"] = function()
  local dir = helpers.create_temp_dir()
  local target = dir .. "/target.txt"
  helpers.create_file(target, "keep target")
  for _, source in ipairs({ target, dir .. "/missing.txt" }) do
    local path = dir .. "/link-" .. vim.fn.fnamemodify(source, ":t")
    assert(vim.uv.fs_symlink(source, path))
    MiniTest.expect.equality(type(create_and_wait(path, false)), "string")
    MiniTest.expect.equality(vim.uv.fs_readlink(path), source)
  end
  MiniTest.expect.equality(vim.fn.readfile(target), { "keep target" })
  MiniTest.expect.equality(vim.uv.fs_stat(dir .. "/missing.txt"), nil)
  helpers.remove_temp_dir(dir)
end

T["create protects a file appearing after preflight"] = function()
  local dir = helpers.create_temp_dir()
  local path = dir .. "/race.txt"
  local operations = { { type = "create", path = path, entry_type = "file" } }
  local store = require("eda.tree.store").new()
  store:set_root(dir)
  MiniTest.expect.equality(require("eda.tree.diff").validate(operations, store).valid, true)
  helpers.create_file(path, "external writer")
  local result
  Fs.execute_operations(operations, { delete_to_trash = false }, function(value)
    result = value
  end)
  helpers.wait_for(3000, function()
    return result ~= nil
  end)
  MiniTest.expect.equality(#result.completed, 0)
  MiniTest.expect.equality(type(result.error), "string")
  MiniTest.expect.equality(vim.fn.readfile(path), { "external writer" })
  helpers.remove_temp_dir(dir)
end

T["create makes missing parents for exclusive files and directories"] = function()
  local dir = helpers.create_temp_dir()
  MiniTest.expect.equality(create_and_wait(dir .. "/a/b/file.txt", false), nil)
  MiniTest.expect.equality(create_and_wait(dir .. "/c/d/nested", true), nil)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/a/b/file.txt"), 1)
  MiniTest.expect.equality(vim.fn.isdirectory(dir .. "/c/d/nested"), 1)
  helpers.remove_temp_dir(dir)
end

T["create preserves filesystem resolution through symlink parents"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_dir(dir .. "/real/nested")
  assert(vim.uv.fs_symlink(dir .. "/real/nested", dir .. "/link"))
  MiniTest.expect.equality(create_and_wait(dir .. "/link/../file.txt", false), nil)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/real/file.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/file.txt"), 0)
  helpers.remove_temp_dir(dir)
end

T["create reports parent errors through its callback"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/parent", "not a directory")
  MiniTest.expect.equality(type(create_and_wait(dir .. "/parent/file.txt", false)), "string")
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/parent"), { "not a directory" })
  helpers.remove_temp_dir(dir)
end

T["execute_operations module loads"] = function()
  MiniTest.expect.equality(type(Fs.create), "function")
  MiniTest.expect.equality(type(Fs.delete), "function")
  MiniTest.expect.equality(type(Fs.move), "function")
  MiniTest.expect.equality(type(Fs.copy), "function")
  MiniTest.expect.equality(type(Fs.trash), "function")
  MiniTest.expect.equality(type(Fs.execute_operations), "function")
end

T["create file"] = function()
  local tmpdir = helpers.create_temp_dir()
  local path = tmpdir .. "/test.lua"

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = io.open(path, "w")
  if f then
    f:write("")
    f:close()
  end

  MiniTest.expect.equality(vim.fn.filereadable(path), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["create nested file with auto-mkdir"] = function()
  local tmpdir = helpers.create_temp_dir()
  local path = tmpdir .. "/a/b/c/nested.lua"

  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = io.open(path, "w")
  if f then
    f:write("")
    f:close()
  end

  MiniTest.expect.equality(vim.fn.filereadable(path), 1)
  MiniTest.expect.equality(vim.fn.isdirectory(tmpdir .. "/a/b/c"), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["create directory"] = function()
  local tmpdir = helpers.create_temp_dir()
  local path = tmpdir .. "/new_dir"

  vim.fn.mkdir(path, "p")
  MiniTest.expect.equality(vim.fn.isdirectory(path), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["create nested directory"] = function()
  local tmpdir = helpers.create_temp_dir()
  local path = tmpdir .. "/x/y/z"

  vim.fn.mkdir(path, "p")
  MiniTest.expect.equality(vim.fn.isdirectory(path), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["delete file"] = function()
  local tmpdir = helpers.create_temp_dir()
  local path = tmpdir .. "/to_delete.lua"
  helpers.create_file(path, "delete me")

  vim.fn.delete(path)
  MiniTest.expect.equality(vim.fn.filereadable(path), 0)
  helpers.remove_temp_dir(tmpdir)
end

T["delete directory recursively"] = function()
  local tmpdir = helpers.create_temp_dir()
  local dir = tmpdir .. "/dir_to_delete"
  helpers.create_dir(dir)
  helpers.create_file(dir .. "/child.txt", "content")

  vim.fn.delete(dir, "rf")
  MiniTest.expect.equality(vim.fn.isdirectory(dir), 0)
  helpers.remove_temp_dir(tmpdir)
end

T["move/rename file"] = function()
  local tmpdir = helpers.create_temp_dir()
  local src = tmpdir .. "/old.lua"
  local dst = tmpdir .. "/new.lua"
  helpers.create_file(src, "content")

  vim.fn.rename(src, dst)
  MiniTest.expect.equality(vim.fn.filereadable(src), 0)
  MiniTest.expect.equality(vim.fn.filereadable(dst), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["move creates parent directory if needed"] = function()
  local tmpdir = helpers.create_temp_dir()
  local src = tmpdir .. "/src.txt"
  local dst = tmpdir .. "/sub/dir/dst.txt"
  helpers.create_file(src, "content")

  vim.fn.mkdir(vim.fn.fnamemodify(dst, ":h"), "p")
  vim.fn.rename(src, dst)
  MiniTest.expect.equality(vim.fn.filereadable(dst), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["copy file via uv"] = function()
  local tmpdir = helpers.create_temp_dir()
  local src = tmpdir .. "/original.lua"
  local dst = tmpdir .. "/copy.lua"
  helpers.create_file(src, "original content")

  local done = false
  vim.uv.fs_copyfile(src, dst, function()
    done = true
  end)
  helpers.wait_for(3000, function()
    return done
  end)

  MiniTest.expect.equality(vim.fn.filereadable(src), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["copy directory recursively"] = function()
  local tmpdir = helpers.create_temp_dir()
  local src = tmpdir .. "/dir_src"
  local dst = tmpdir .. "/dir_dst"
  helpers.create_dir(src)
  helpers.create_file(src .. "/a.txt", "a")
  helpers.create_dir(src .. "/sub")
  helpers.create_file(src .. "/sub/b.txt", "b")

  vim.fn.system({ "cp", "-R", src, dst })
  MiniTest.expect.equality(vim.fn.isdirectory(dst), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst .. "/a.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst .. "/sub/b.txt"), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["Fs.execute_operations empty list succeeds synchronously"] = function()
  -- execute_operations with empty list calls cb synchronously (no vim.schedule)
  local exec_result
  Fs.execute_operations({}, { delete_to_trash = false }, function(result)
    exec_result = result
  end)
  MiniTest.expect.equality(exec_result ~= nil, true)
  MiniTest.expect.equality(exec_result.error, nil)
  MiniTest.expect.equality(#exec_result.completed, 0)
end

T["Fs.execute_operations runs all ops and reports success"] = function()
  local tmpdir = helpers.create_temp_dir()
  helpers.create_file(tmpdir .. "/file1.txt", "content1")

  local ops = {
    { type = "create", path = tmpdir .. "/new_file.txt", entry_type = "file" },
    { type = "move", src = tmpdir .. "/file1.txt", dst = tmpdir .. "/moved.txt", path = tmpdir .. "/moved.txt" },
  }

  local exec_result
  Fs.execute_operations(ops, { delete_to_trash = false }, function(result)
    exec_result = result
  end)

  helpers.wait_for(5000, function()
    return exec_result ~= nil
  end)

  MiniTest.expect.equality(exec_result.error, nil)
  MiniTest.expect.equality(#exec_result.completed, 2)
  MiniTest.expect.equality(vim.fn.filereadable(tmpdir .. "/new_file.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmpdir .. "/moved.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmpdir .. "/file1.txt"), 0)
  helpers.remove_temp_dir(tmpdir)
end

T["Fs.execute_operations halts on first error"] = function()
  local tmpdir = helpers.create_temp_dir()
  helpers.create_file(tmpdir .. "/file1.txt", "content1")

  local ops = {
    { type = "create", path = tmpdir .. "/ok.txt", entry_type = "file" },
    { type = "move", src = tmpdir .. "/nonexistent.txt", dst = tmpdir .. "/moved.txt", path = tmpdir .. "/moved.txt" },
    { type = "create", path = tmpdir .. "/should_not_run.txt", entry_type = "file" },
  }

  local exec_result
  Fs.execute_operations(ops, { delete_to_trash = false }, function(result)
    exec_result = result
  end)

  helpers.wait_for(5000, function()
    return exec_result ~= nil
  end)

  MiniTest.expect.equality(exec_result.error ~= nil, true)
  MiniTest.expect.equality(#exec_result.completed, 1)
  MiniTest.expect.equality(exec_result.failed.type, "move")
  -- Third op should not have run
  MiniTest.expect.equality(vim.fn.filereadable(tmpdir .. "/should_not_run.txt"), 0)
  helpers.remove_temp_dir(tmpdir)
end

T["Fs.trash rejects path with newline"] = function()
  local err_msg
  local path_with_newline = "/tmp/test" .. string.char(10) .. "file"
  Fs.trash(path_with_newline, function(err)
    err_msg = err
  end)
  MiniTest.expect.equality(type(err_msg), "string")
  MiniTest.expect.equality(err_msg:find("control characters") ~= nil, true)
end

T["Fs.trash rejects path with carriage return"] = function()
  local err_msg
  local path_with_cr = "/tmp/test" .. string.char(13) .. "file"
  Fs.trash(path_with_cr, function(err)
    err_msg = err
  end)
  MiniTest.expect.equality(type(err_msg), "string")
  MiniTest.expect.equality(err_msg:find("control characters") ~= nil, true)
end

T["Fs.copy copies directory recursively"] = function()
  local tmpdir = helpers.create_temp_dir()
  local src = tmpdir .. "/src_dir"
  local dst = tmpdir .. "/dst_dir"
  helpers.create_dir(src)
  helpers.create_file(src .. "/child.txt", "child_content")
  helpers.create_dir(src .. "/nested")
  helpers.create_file(src .. "/nested/deep.txt", "deep_content")

  local done = false
  local copy_err
  Fs.copy(src, dst, function(err)
    copy_err = err
    done = true
  end)

  helpers.wait_for(5000, function()
    return done
  end)

  MiniTest.expect.equality(copy_err, nil)
  MiniTest.expect.equality(vim.fn.isdirectory(dst), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst .. "/child.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dst .. "/nested/deep.txt"), 1)
  helpers.remove_temp_dir(tmpdir)
end

T["Fs.move reports parent creation failure without removing the source"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/source", "source")
  helpers.create_file(dir .. "/blocked", "blocker")
  local result
  Fs.move(dir .. "/source", dir .. "/blocked/target", function(err)
    result = err or false
  end)
  helpers.wait_for(5000, function()
    return result ~= nil
  end)
  MiniTest.expect.equality(type(result), "string")
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/source"), { "source" })
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/blocked"), { "blocker" })
  helpers.remove_temp_dir(dir)
end

return T
