local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/a/nested/file", "A")
      e2e.create_file(tmp .. "/b/keep", "B")
      e2e.create_file(tmp .. "/root_file", "ROOT")
      e2e.exec(
        child,
        [[
        _G.callbacks, _G.scans = {}, {}
        local Watcher = require("eda.watcher")
        local watch = Watcher.watch
        Watcher.watch = function(self, path, callback)
          _G.callbacks[path] = callback
          watch(self, path, function(...)
            if not _G.mute_watch_events then
              _G.watch_events = (_G.watch_events or 0) + 1
              callback(...)
            end
          end)
        end
        local Scanner = require("eda.tree.scanner")
        local scan = Scanner._do_scan_io
        Scanner._do_scan_io = function(self, id, ...)
          table.insert(_G.scans, self.store:get(id).path)
          return scan(self, id, ...)
        end
      ]]
      )
      e2e.open_eda(child, tmp)
      e2e.feed(child, "gE")
      e2e.wait_until(child, [[#require("eda").get_current().buffer.flat_lines == 6]])
      e2e.exec(
        child,
        [[
        local ex = require("eda").get_current()
        _G.original = ex.store:get_by_path(ex.root_path .. "/b/keep")
        _G.scans, _G.paints = {}, 0
        local paint = ex.buffer.painter.paint
        ex.buffer.painter.paint = function(self, ...)
          _G.paints = _G.paints + 1
          return paint(self, ...)
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

for _, operation in ipairs({ "create", "rename", "delete" }) do
  T["observes real nested " .. operation .. " without scanning unrelated subtrees"] = function()
    MiniTest.expect.equality(
      e2e.exec(child, [[return vim.tbl_count(require("eda").get_current().watcher._handles)]]),
      4
    )
    if operation == "create" then
      e2e.create_file(tmp .. "/a/nested/added", "NEW")
    elseif operation == "rename" then
      assert(vim.uv.fs_rename(tmp .. "/a/nested/file", tmp .. "/a/nested/added"))
    else
      assert(vim.uv.fs_unlink(tmp .. "/a/nested/file"))
    end
    e2e.wait_until(
      child,
      string.format(
        [[
      local ex = require("eda").get_current()
      local file = ex.store:get_by_path(ex.root_path .. "/a/nested/file")
      local added = ex.store:get_by_path(ex.root_path .. "/a/nested/added")
      return %s and not ex.refresh.pending and not ex.refresh.running
    ]],
        operation == "create" and "file ~= nil and added ~= nil"
          or operation == "rename" and "file == nil and added ~= nil"
          or "file == nil and added == nil"
      )
    )
    MiniTest.expect.equality(
      e2e.exec(
        child,
        [[
      local ex = require("eda").get_current()
      for _, path in ipairs(_G.scans) do
        if path == ex.root_path .. "/b" then return false end
      end
      return ex.store:get_by_path(ex.root_path .. "/b/keep") == _G.original
    ]]
      ),
      true
    )
  end
end

T["coalesces known bursts and skips unchanged echo paints"] = function()
  MiniTest.expect.equality(
    e2e.exec(child, [[return _G.callbacks[require("eda").get_current().root_path .. "/a/nested"] ~= nil]]),
    true
  )
  e2e.exec(
    child,
    [[
    local ex = require("eda").get_current()
    _G.mute_watch_events = true
    vim.fn.writefile({ "NEW" }, ex.root_path .. "/a/nested/added")
    for _ = 1, 25 do _G.callbacks[ex.root_path .. "/a/nested"]("added", { rename = true }) end
  ]]
  )
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return ex.store:get_by_path(ex.root_path .. "/a/nested/added") ~= nil
      and not ex.refresh.pending and not ex.refresh.running
  ]]
  )
  MiniTest.expect.equality(e2e.exec(child, "return { #_G.scans, _G.paints }"), { 1, 1 })
  e2e.exec(
    child,
    [[
    local ex = require("eda").get_current()
    _G.callbacks[ex.root_path .. "/a/nested"]("added", { rename = true })
  ]]
  )
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return #_G.scans == 2 and not ex.refresh.pending and not ex.refresh.running
  ]]
  )
  MiniTest.expect.equality(e2e.exec(child, "return _G.paints"), 1)
end

T["bounds handles across repeated collapse expand root change and close"] = function()
  for _ = 1, 5 do
    e2e.exec(child, [[vim.fn.search("^a/$", "w")]])
    e2e.feed(child, "<CR>")
    e2e.wait_until(
      child,
      [[not require("eda").get_current().store:get_by_path(require("eda").get_current().root_path .. "/a").open]]
    )
    MiniTest.expect.equality(
      e2e.exec(child, [[return vim.tbl_count(require("eda").get_current().watcher._handles)]]),
      2
    )
    e2e.feed(child, "<CR>")
    e2e.wait_until(child, [[vim.tbl_count(require("eda").get_current().watcher._handles) == 4]])
  end
  e2e.exec(
    child,
    [[
    _G.explorer = require("eda").get_current()
    require("eda")._change_root(_G.explorer, _G.explorer.root_path .. "/b")
  ]]
  )
  e2e.wait_until(child, "_G.explorer._initial_scan_complete")
  MiniTest.expect.equality(e2e.exec(child, "return vim.tbl_count(_G.explorer.watcher._handles)"), 1)
  e2e.exec(child, [[require("eda").close()]])
  MiniTest.expect.equality(e2e.exec(child, "return vim.tbl_count(_G.explorer.watcher._handles)"), 0)
end

T["unknown event scope refreshes open subtrees while retaining identities"] = function()
  e2e.exec(
    child,
    [[
    local ex = require("eda").get_current()
    _G.mute_watch_events = true
    vim.fn.writefile({ "NEW" }, ex.root_path .. "/a/nested/added")
    _G.callbacks[ex.root_path]()
  ]]
  )
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return ex.store:get_by_path(ex.root_path .. "/a/nested/added") ~= nil
      and not ex.refresh.pending and not ex.refresh.running
  ]]
  )
  MiniTest.expect.equality(e2e.exec(child, "return #_G.scans"), 4)
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    return ex.store:get_by_path(ex.root_path .. "/b/keep") == _G.original
  ]]
    ),
    true
  )
end

T["defers a nested event until undo discards unsaved edits"] = function()
  e2e.exec(child, [[vim.fn.search("^root_file$", "w")]])
  e2e.feed(child, "dd")
  e2e.wait_until(child, "vim.bo.modified")
  local lines = e2e.get_buf_lines(child)
  e2e.create_file(tmp .. "/a/nested/added", "NEW")
  e2e.wait_until(child, [[require("eda").get_current().refresh.pending]])
  MiniTest.expect.equality(e2e.get_buf_lines(child), lines)
  MiniTest.expect.equality(e2e.exec(child, "return #_G.scans"), 0)
  e2e.feed(child, "u")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not ex.refresh.pending and not ex.refresh.running
      and ex.store:get_by_path(ex.root_path .. "/a/nested/added") ~= nil
  ]]
  )
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/root_file"), { "ROOT" })
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    return ex.store:get_by_path(ex.root_path .. "/b/keep") == _G.original
  ]]
    ),
    true
  )
end

T["coalesces save echoes into one scoped scan without an extra paint"] = function()
  e2e.exec(
    child,
    [[
    _G.mute_watch_events = true
    vim.api.nvim_create_autocmd("User", {
      pattern = "EdaMutationPost",
      once = true,
      callback = function()
        local ex = require("eda").get_current()
        for _ = 1, 25 do _G.callbacks[ex.root_path]("new1", { rename = true }) end
      end,
    })
  ]]
  )
  e2e.feed(child, "Go")
  e2e.feed_insert(child, "new1\nnew2\nnew3")
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not ex._writing and not ex.refresh.pending and not ex.refresh.running
      and ex.store:get_by_path(ex.root_path .. "/new3") ~= nil
  ]]
  )
  MiniTest.expect.equality(e2e.exec(child, "return { #_G.scans, _G.paints }"), { 5, 1 })
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    return ex.store:get_by_path(ex.root_path .. "/b/keep") == _G.original
  ]]
    ),
    true
  )
end

return T
