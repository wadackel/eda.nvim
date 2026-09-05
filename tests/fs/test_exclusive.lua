local Fs = require("eda.fs")
local helpers = require("helpers")
local tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = helpers.create_temp_dir()
    end,
    post_case = function()
      helpers.remove_temp_dir(tmp)
    end,
  },
})

local function transfer(operation, src, dst)
  local finished, result, fast = false, nil, nil
  Fs[operation](src, dst, function(err)
    result, fast, finished = err, vim.in_fast_event(), true
  end, { no_replace = true })
  helpers.wait_for(5000, function()
    return finished
  end)
  MiniTest.expect.equality(finished, true)
  MiniTest.expect.equality(fast, false)
  return result
end

for _, operation in ipairs({ "copy", "move" }) do
  T[operation .. " preserves existing files directories and broken links"] = function()
    helpers.create_file(tmp .. "/source", "SOURCE")
    helpers.create_file(tmp .. "/file", "KEEP")
    helpers.create_file(tmp .. "/dir/inside", "INSIDE")
    assert(vim.uv.fs_symlink(tmp .. "/missing", tmp .. "/link"))
    for _, name in ipairs({ "file", "dir", "link" }) do
      MiniTest.expect.equality(type(transfer(operation, tmp .. "/source", tmp .. "/" .. name)), "string")
      MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "SOURCE" })
    end
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/file"), { "KEEP" })
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dir/inside"), { "INSIDE" })
    MiniTest.expect.equality(vim.uv.fs_readlink(tmp .. "/link"), tmp .. "/missing")
  end

  T[operation .. " preserves the text of symlinks"] = function()
    helpers.create_file(tmp .. "/source", "SOURCE")
    assert(vim.uv.fs_symlink("source", tmp .. "/link"))
    MiniTest.expect.equality(transfer(operation, tmp .. "/link", tmp .. "/nested/link"), nil)
    MiniTest.expect.equality(vim.uv.fs_readlink(tmp .. "/nested/link"), "source")
    MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/link") ~= nil, operation == "copy")
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "SOURCE" })
  end
end

T["copy preserves nested files hidden entries and directory permissions"] = function()
  helpers.create_file(tmp .. "/src/nested/file", "FILE")
  helpers.create_file(tmp .. "/src/.hidden", "HIDDEN")
  assert(vim.uv.fs_symlink("nested/file", tmp .. "/src/link"))
  MiniTest.expect.equality(transfer("copy", tmp .. "/src", tmp .. "/dst"), nil)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dst/nested/file"), { "FILE" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dst/.hidden"), { "HIDDEN" })
  MiniTest.expect.equality(vim.uv.fs_readlink(tmp .. "/dst/link"), "nested/file")
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/dst").mode, vim.uv.fs_stat(tmp .. "/src").mode)
end

T["move refuses an existing empty directory"] = function()
  helpers.create_file(tmp .. "/src/file", "FILE")
  assert(vim.uv.fs_mkdir(tmp .. "/dst", 493))
  MiniTest.expect.equality(type(transfer("move", tmp .. "/src", tmp .. "/dst")), "string")
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/src/file"), { "FILE" })
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/dst/file"), nil)
end

T["cross-device move copies exclusively before removing its source"] = function()
  helpers.create_file(tmp .. "/source", "SOURCE")
  local link = vim.uv.fs_link
  vim.uv.fs_link = function(_, _, callback)
    callback("EXDEV: injected cross-device link")
  end
  local ok, err = pcall(transfer, "move", tmp .. "/source", tmp .. "/dest")
  vim.uv.fs_link = link
  assert(ok, err)
  MiniTest.expect.equality(err, nil)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest"), { "SOURCE" })
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/source"), nil)
end

T["cross-device fallback does not overwrite a destination"] = function()
  helpers.create_file(tmp .. "/source", "SOURCE")
  helpers.create_file(tmp .. "/dest", "KEEP")
  local link = vim.uv.fs_link
  vim.uv.fs_link = function(_, _, callback)
    callback("EXDEV: injected cross-device link")
  end
  local ok, err = pcall(transfer, "move", tmp .. "/source", tmp .. "/dest")
  vim.uv.fs_link = link
  assert(ok, err)
  MiniTest.expect.equality(type(err), "string")
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest"), { "KEEP" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "SOURCE" })
end

T["unlink failure retains both source and destination"] = function()
  helpers.create_file(tmp .. "/source", "SOURCE")
  local unlink = vim.uv.fs_unlink
  vim.uv.fs_unlink = function(_, callback)
    callback("EACCES: injected unlink failure")
  end
  local ok, err = pcall(transfer, "move", tmp .. "/source", tmp .. "/dest")
  vim.uv.fs_unlink = unlink
  assert(ok, err)
  MiniTest.expect.equality(type(err), "string")
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest"), { "SOURCE" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "SOURCE" })
end

return T
