local Fs = require("eda.fs")
local helpers = require("helpers")

local tmpdir
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmpdir = helpers.create_temp_dir()
    end,
    post_case = function()
      helpers.remove_temp_dir(tmpdir)
    end,
  },
})

local function await_callback(start)
  local calls, result, fast = 0, nil, false
  start(function(value)
    calls, result = calls + 1, value
    fast = fast or vim.in_fast_event()
  end)
  MiniTest.expect.equality(
    helpers.wait_for(5000, function()
      return calls > 0
    end),
    true
  )
  local drained = false
  vim.schedule(function()
    drained = true
  end)
  MiniTest.expect.equality(
    helpers.wait_for(5000, function()
      return drained
    end),
    true
  )
  MiniTest.expect.equality(calls, 1)
  MiniTest.expect.equality(fast, false)
  return result
end

local function create_and_wait(path, is_dir)
  return await_callback(function(cb)
    Fs.create(path, is_dir, cb)
  end)
end

local function read_bytes(path)
  local file = assert(io.open(path, "rb"))
  local contents = file:read("*a")
  file:close()
  return contents
end

T["create rejects an existing file without changing its contents"] = function()
  local dir = tmpdir
  local path = dir .. "/keep.txt"
  helpers.create_file(path, "keep this content")
  MiniTest.expect.equality(type(create_and_wait(path, false)), "string")
  MiniTest.expect.equality(vim.fn.readfile(path), { "keep this content" })
end

T["create rejects an existing directory"] = function()
  local dir = tmpdir
  MiniTest.expect.equality(type(create_and_wait(dir, true)), "string")
  MiniTest.expect.equality(vim.fn.isdirectory(dir), 1)
end

T["create rejects valid and broken symlink destinations"] = function()
  local dir = tmpdir
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
end

T["create protects a file appearing after preflight"] = function()
  local dir = tmpdir
  local path = dir .. "/race.txt"
  local operations = { { type = "create", path = path, entry_type = "file" } }
  local store = require("eda.tree.store").new()
  store:set_root(dir)
  MiniTest.expect.equality(require("eda.tree.diff").validate(operations, store).valid, true)
  helpers.create_file(path, "external writer")
  local result = await_callback(function(cb)
    Fs.execute_operations(operations, { delete_to_trash = false }, cb)
  end)
  MiniTest.expect.equality(#result.completed, 0)
  MiniTest.expect.equality(type(result.error), "string")
  MiniTest.expect.equality(vim.fn.readfile(path), { "external writer" })
end

T["create makes missing parents for exclusive files and directories"] = function()
  local dir = tmpdir
  MiniTest.expect.equality(create_and_wait(dir .. "/a/b/file.txt", false), nil)
  MiniTest.expect.equality(create_and_wait(dir .. "/c/d/nested", true), nil)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/a/b/file.txt"), 1)
  MiniTest.expect.equality(vim.fn.isdirectory(dir .. "/c/d/nested"), 1)
end

T["create preserves filesystem resolution through symlink parents"] = function()
  local dir = tmpdir
  helpers.create_dir(dir .. "/real/nested")
  assert(vim.uv.fs_symlink(dir .. "/real/nested", dir .. "/link"))
  MiniTest.expect.equality(create_and_wait(dir .. "/link/../file.txt", false), nil)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/real/file.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(dir .. "/file.txt"), 0)
end

T["create reports parent errors through its callback"] = function()
  local dir = tmpdir
  helpers.create_file(dir .. "/parent", "not a directory")
  MiniTest.expect.equality(type(create_and_wait(dir .. "/parent/file.txt", false)), "string")
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/parent"), { "not a directory" })
end

T["create file"] = function()
  local path = tmpdir .. "/test.lua"
  MiniTest.expect.equality(create_and_wait(path, false), nil)
  MiniTest.expect.equality(read_bytes(path), "")
end

T["create nested file with auto-mkdir"] = function()
  local path = tmpdir .. "/a/b/c/nested.lua"
  MiniTest.expect.equality(create_and_wait(path, false), nil)
  MiniTest.expect.equality(read_bytes(path), "")
  MiniTest.expect.equality(vim.fn.isdirectory(tmpdir .. "/a/b/c"), 1)
end

for _, name in ipairs({ "new_dir", "x/y/z" }) do
  T["create directory " .. name] = function()
    local path = tmpdir .. "/" .. name
    MiniTest.expect.equality(create_and_wait(path, true), nil)
    MiniTest.expect.equality(vim.fn.isdirectory(path), 1)
    MiniTest.expect.equality(vim.fn.readdir(path), {})
  end
end

T["delete file"] = function()
  local path = tmpdir .. "/to_delete.lua"
  helpers.create_file(path, "delete me")
  helpers.create_file(tmpdir .. "/keep", "KEEP")
  MiniTest.expect.equality(
    await_callback(function(cb)
      Fs.delete(path, cb)
    end),
    nil
  )
  MiniTest.expect.equality(vim.uv.fs_lstat(path), nil)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/keep"), "KEEP")
end

T["delete directory recursively"] = function()
  local dir = tmpdir .. "/dir_to_delete"
  helpers.create_file(dir .. "/child.txt", "content")
  helpers.create_file(dir .. "/nested/.hidden", "hidden")
  helpers.create_file(tmpdir .. "/keep", "KEEP")
  MiniTest.expect.equality(
    await_callback(function(cb)
      Fs.delete(dir, cb)
    end),
    nil
  )
  MiniTest.expect.equality(vim.uv.fs_lstat(dir), nil)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/keep"), "KEEP")
end

for _, target in ipairs({ "target", "target/keep", "missing" }) do
  T["delete symlink to " .. target .. " preserves target contents"] = function()
    helpers.create_file(tmpdir .. "/target/keep", "KEEP")
    assert(vim.uv.fs_symlink(tmpdir .. "/" .. target, tmpdir .. "/link"))
    local err = await_callback(function(cb)
      Fs.delete(tmpdir .. "/link", cb)
    end)
    MiniTest.expect.equality(read_bytes(tmpdir .. "/target/keep"), "KEEP")
    MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/missing"), nil)
    MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/link"), nil)
    MiniTest.expect.equality(err, nil)
  end
end

T["delete directory leaves nested symlink targets intact"] = function()
  helpers.create_file(tmpdir .. "/target/keep", "KEEP")
  helpers.create_file(tmpdir .. "/remove/nested/file", "DELETE")
  assert(vim.uv.fs_symlink(tmpdir .. "/target", tmpdir .. "/remove/nested/link"))
  local err = await_callback(function(cb)
    Fs.delete(tmpdir .. "/remove", cb)
  end)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/target/keep"), "KEEP")
  MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/remove"), nil)
  MiniTest.expect.equality(err, nil)
end

T["delete reports unlink failure and retains the link and target"] = function()
  helpers.create_file(tmpdir .. "/target", "KEEP")
  assert(vim.uv.fs_symlink("target", tmpdir .. "/link"))
  local unlink = vim.uv.fs_unlink
  vim.uv.fs_unlink = function()
    return nil, "EACCES: injected unlink failure"
  end
  local ok, err = pcall(await_callback, function(cb)
    Fs.delete(tmpdir .. "/link", cb)
  end)
  vim.uv.fs_unlink = unlink
  assert(ok, err)
  MiniTest.expect.equality(type(err), "string")
  MiniTest.expect.equality(err:find("EACCES", 1, true) ~= nil, true)
  MiniTest.expect.equality(vim.uv.fs_readlink(tmpdir .. "/link"), "target")
  MiniTest.expect.equality(read_bytes(tmpdir .. "/target"), "KEEP")
end

T["delete missing path succeeds without changing its neighbors"] = function()
  helpers.create_file(tmpdir .. "/keep", "KEEP")
  MiniTest.expect.equality(
    await_callback(function(cb)
      Fs.delete(tmpdir .. "/missing", cb)
    end),
    nil
  )
  MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/missing"), nil)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/keep"), "KEEP")
end

for _, operation in ipairs({ "move", "copy" }) do
  for _, destination in ipairs({ "new file's.bin", "sub/dir/new file's.bin" }) do
    T[operation .. " preserves file bytes at " .. destination] = function()
      local src, dst = tmpdir .. "/source file's.bin", tmpdir .. "/" .. destination
      local contents = "first\0second\nlast\255"
      helpers.create_file(src, contents)
      MiniTest.expect.equality(
        await_callback(function(cb)
          Fs[operation](src, dst, cb)
        end),
        nil
      )
      MiniTest.expect.equality(read_bytes(dst), contents)
      if operation == "copy" then
        MiniTest.expect.equality(read_bytes(src), contents)
      else
        MiniTest.expect.equality(vim.uv.fs_lstat(src), nil)
      end
    end
  end

  T[operation .. " reports a missing source without changing the destination"] = function()
    local dst = tmpdir .. "/keep"
    helpers.create_file(dst, "KEEP")
    MiniTest.expect.equality(
      type(await_callback(function(cb)
        Fs[operation](tmpdir .. "/missing", dst, cb)
      end)),
      "string"
    )
    MiniTest.expect.equality(read_bytes(dst), "KEEP")
    MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/missing"), nil)
  end

  T[operation .. " reports a missing source without creating a destination"] = function()
    local dst = tmpdir .. "/nested/absent"
    MiniTest.expect.equality(
      type(await_callback(function(cb)
        Fs[operation](tmpdir .. "/missing", dst, cb)
      end)),
      "string"
    )
    MiniTest.expect.equality(vim.uv.fs_lstat(dst), nil)
  end

  T[operation .. " preserves recursive contents and empty directories"] = function()
    local src, dst = tmpdir .. "/src", tmpdir .. "/parent/dst"
    helpers.create_file(src .. "/child.txt", "child\0content")
    helpers.create_file(src .. "/nested/.hidden", "hidden\ncontent")
    helpers.create_dir(src .. "/empty")
    MiniTest.expect.equality(
      await_callback(function(cb)
        Fs[operation](src, dst, cb)
      end),
      nil
    )
    MiniTest.expect.equality(read_bytes(dst .. "/child.txt"), "child\0content")
    MiniTest.expect.equality(read_bytes(dst .. "/nested/.hidden"), "hidden\ncontent")
    MiniTest.expect.equality(vim.fn.isdirectory(dst .. "/empty"), 1)
    MiniTest.expect.equality(vim.fn.readdir(dst .. "/empty"), {})
    if operation == "copy" then
      MiniTest.expect.equality(read_bytes(src .. "/child.txt"), "child\0content")
      MiniTest.expect.equality(read_bytes(src .. "/nested/.hidden"), "hidden\ncontent")
      MiniTest.expect.equality(vim.fn.isdirectory(src .. "/empty"), 1)
    else
      MiniTest.expect.equality(vim.uv.fs_lstat(src), nil)
    end
  end
end

T["Fs.execute_operations empty list succeeds synchronously"] = function()
  local exec_result
  Fs.execute_operations({}, { delete_to_trash = false }, function(result)
    exec_result = result
  end)
  MiniTest.expect.equality(exec_result ~= nil, true)
  MiniTest.expect.equality(exec_result.error, nil)
  MiniTest.expect.equality(#exec_result.completed, 0)
end

T["Fs.execute_operations runs all ops and reports success"] = function()
  helpers.create_file(tmpdir .. "/file1.txt", "content1")

  local ops = {
    { type = "create", path = tmpdir .. "/new_file.txt", entry_type = "file" },
    { type = "move", src = tmpdir .. "/file1.txt", dst = tmpdir .. "/moved.txt", path = tmpdir .. "/moved.txt" },
  }

  local exec_result = await_callback(function(cb)
    Fs.execute_operations(ops, { delete_to_trash = false }, cb)
  end)

  MiniTest.expect.equality(exec_result.error, nil)
  MiniTest.expect.equality(exec_result.completed, ops)
  MiniTest.expect.equality(exec_result.failed, nil)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/new_file.txt"), "")
  MiniTest.expect.equality(read_bytes(tmpdir .. "/moved.txt"), "content1")
  MiniTest.expect.equality(vim.fn.filereadable(tmpdir .. "/file1.txt"), 0)
end

T["Fs.execute_operations halts on first error"] = function()
  helpers.create_file(tmpdir .. "/file1.txt", "content1")

  local ops = {
    { type = "create", path = tmpdir .. "/ok.txt", entry_type = "file" },
    { type = "move", src = tmpdir .. "/nonexistent.txt", dst = tmpdir .. "/moved.txt", path = tmpdir .. "/moved.txt" },
    { type = "delete", path = tmpdir .. "/file1.txt" },
  }

  local exec_result = await_callback(function(cb)
    Fs.execute_operations(ops, { delete_to_trash = false }, cb)
  end)

  MiniTest.expect.equality(type(exec_result.error), "string")
  MiniTest.expect.equality(exec_result.completed, { ops[1] })
  MiniTest.expect.equality(exec_result.failed, ops[2])
  MiniTest.expect.equality(read_bytes(tmpdir .. "/ok.txt"), "")
  MiniTest.expect.equality(vim.uv.fs_lstat(tmpdir .. "/moved.txt"), nil)
  MiniTest.expect.equality(read_bytes(tmpdir .. "/file1.txt"), "content1")
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

T["Fs.move reports parent creation failure without removing the source"] = function()
  local dir = tmpdir
  helpers.create_file(dir .. "/source", "source")
  helpers.create_file(dir .. "/blocked", "blocker")
  local result = await_callback(function(cb)
    Fs.move(dir .. "/source", dir .. "/blocked/target", cb)
  end)
  MiniTest.expect.equality(type(result), "string")
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/source"), { "source" })
  MiniTest.expect.equality(vim.fn.readfile(dir .. "/blocked"), { "blocker" })
end

return T
