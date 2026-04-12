local Fs = require("eda.fs")
local helpers = require("helpers")

local T = MiniTest.new_set()

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

return T
