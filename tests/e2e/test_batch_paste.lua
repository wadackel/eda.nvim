local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/a/file.txt", "A")
      e2e.create_file(tmp .. "/b/file.txt", "B")
      e2e.create_file(tmp .. "/dest/keep", "KEEP")
      e2e.exec(
        child,
        [[
        local notify = vim.notify
        vim.notify = function(message, level)
          if level == vim.log.levels.ERROR then _G.paste_error = message end
          if level == vim.log.levels.WARN then _G.paste_warning = message end
          notify(message, level)
        end
      ]]
      )
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

local function seed(operation, extra)
  e2e.open_eda(child, tmp .. "/dest")
  e2e.exec(child, [[vim.fn.search("keep", "w")]])
  e2e.exec(
    child,
    string.format(
      [[
    require("eda.register").set({ %q, %q%s }, %q)
  ]],
      tmp .. "/a/file.txt",
      tmp .. "/b/file.txt",
      extra and ", " .. string.format("%q", extra) or "",
      operation
    )
  )
end

for _, operation in ipairs({ "copy", "cut" }) do
  T[operation .. " preserves both same-named source contents"] = function()
    seed(operation)
    e2e.feed(child, "gp")
    e2e.wait_until(child, [[require("eda.register").get() == nil]])
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file.txt"), { "A" })
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy.txt"), { "B" })
    MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a/file.txt"), operation == "copy" and 1 or 0)
    MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/b/file.txt"), operation == "copy" and 1 or 0)
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/keep"), { "KEEP" })
  end
end

T["reserves suffixes around files directories and broken symlinks"] = function()
  for _, name in ipairs({ "file.txt", "file_copy.txt", "file_copy_2.txt" }) do
    e2e.create_file(tmp .. "/dest/" .. name, name)
  end
  e2e.create_file(tmp .. "/dest/file_copy_3.txt/inside", "inside")
  assert(vim.uv.fs_symlink(tmp .. "/missing", tmp .. "/dest/file_copy_4.txt"))
  seed("copy")
  e2e.feed(child, "gp")
  e2e.wait_until(child, [[require("eda.register").get() == nil]])
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy_5.txt"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy_6.txt"), { "B" })
  for _, name in ipairs({ "file.txt", "file_copy.txt", "file_copy_2.txt" }) do
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/" .. name), { name })
  end
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy_3.txt/inside"), { "inside" })
  MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/dest/file_copy_4.txt").type, "link")
end

T["retries only failed and unattempted cut entries"] = function()
  e2e.create_file(tmp .. "/c/file.txt", "C")
  seed("cut", tmp .. "/c/file.txt")
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    local move = Fs.move
    _G.moves = 0
    Fs.move = function(src, dst, callback, opts)
      _G.moves = _G.moves + 1
      if _G.moves == 2 then callback("injected failure")
      else move(src, dst, callback, opts) end
    end
  ]]
  )
  e2e.feed(child, "gp")
  e2e.wait_until(child, "_G.paste_error ~= nil")
  MiniTest.expect.equality(
    e2e.exec(child, [[return require("eda.register").get().paths]]),
    { tmp .. "/b/file.txt", tmp .. "/c/file.txt" }
  )
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/c/file.txt"), { "C" })
  e2e.feed(child, "gp")
  e2e.wait_until(child, [[require("eda.register").get() == nil]])
  MiniTest.expect.equality(e2e.exec(child, "return _G.moves"), 4)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file.txt"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy.txt"), { "B" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file_copy_2.txt"), { "C" })
end

for _, operation in ipairs({ "copy", "cut" }) do
  T[operation .. " rejects a destination occupied after planning"] = function()
    seed(operation)
    e2e.exec(
      child,
      string.format(
        [[
      local Fs = require("eda.fs")
      local original = Fs[%q]
      Fs[%q] = function(src, dst, callback, opts)
        Fs[%q] = original
        vim.fn.writefile({ "external" }, dst)
        original(src, dst, callback, opts)
      end
    ]],
        operation == "cut" and "move" or "copy",
        operation == "cut" and "move" or "copy",
        operation == "cut" and "move" or "copy"
      )
    )
    e2e.feed(child, "gp")
    e2e.wait_until(child, "_G.paste_error ~= nil")
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/file.txt"), { "external" })
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/a/file.txt"), { "A" })
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/b/file.txt"), { "B" })
    MiniTest.expect.equality(e2e.exec(child, [[return #require("eda.register").get().paths]]), 2)
  end
end

T["keeps a replacement register and ignores a repeated pending paste"] = function()
  seed("copy")
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    local original = Fs.copy
    _G.copies = 0
    _G.completed = 0
    Fs.copy = function(src, dst, callback, opts)
      _G.copies = _G.copies + 1
      local complete = function(err)
        callback(err)
        _G.completed = _G.completed + 1
      end
      if _G.copies == 1 then
        _G.finish_copy = function() original(src, dst, complete, opts) end
      else
        original(src, dst, complete, opts)
      end
    end
  ]]
  )
  e2e.feed(child, "gp")
  e2e.wait_until(child, "_G.finish_copy ~= nil")
  e2e.feed(child, "gp")
  e2e.wait_until(child, "_G.paste_warning ~= nil")
  e2e.exec(
    child,
    [[
    require("eda.register").set({ "/replacement" }, "cut")
    _G.finish_copy()
  ]]
  )
  e2e.wait_until(child, "_G.completed == 2")
  MiniTest.expect.equality(e2e.exec(child, "return _G.copies"), 2)
  MiniTest.expect.equality(e2e.exec(child, [[return require("eda.register").get().paths]]), { "/replacement" })
end

for _, operation in ipairs({ "copy", "cut" }) do
  T[operation .. " preserves same-named directories and symlinks"] = function()
    e2e.create_file(tmp .. "/a/tree/nested", "A")
    e2e.create_file(tmp .. "/b/tree/nested", "B")
    assert(vim.uv.fs_symlink("file.txt", tmp .. "/a/link"))
    assert(vim.uv.fs_symlink("missing", tmp .. "/b/link"))
    seed(operation)
    e2e.exec(
      child,
      string.format(
        [[
      require("eda.register").set({ %q, %q, %q, %q }, %q)
    ]],
        tmp .. "/a/tree",
        tmp .. "/b/tree",
        tmp .. "/a/link",
        tmp .. "/b/link",
        operation
      )
    )
    e2e.feed(child, "gp")
    e2e.wait_until(child, [[require("eda.register").get() == nil]])
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/tree/nested"), { "A" })
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/tree_copy/nested"), { "B" })
    MiniTest.expect.equality(vim.uv.fs_readlink(tmp .. "/dest/link"), "file.txt")
    MiniTest.expect.equality(vim.uv.fs_readlink(tmp .. "/dest/link_copy"), "missing")
    MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/a/tree") ~= nil, operation == "copy")
    MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/b/link") ~= nil, operation == "copy")
  end
end

T["rejects copying a directory into a symlink alias of itself"] = function()
  assert(vim.uv.fs_symlink(tmp .. "/dest", tmp .. "/alias"))
  seed("copy")
  e2e.exec(child, string.format([[require("eda.register").set({ %q }, "copy")]], tmp .. "/alias"))
  e2e.feed(child, "gp")
  e2e.wait_until(child, "_G.paste_error ~= nil")
  MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/dest/alias"), nil)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/keep"), { "KEEP" })
end

return T
