local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["refresh"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/existing.txt", "exists")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["refresh"]["reflects externally added file after Ctrl-L"] = function()
  e2e.open_eda(child, tmp)

  -- Verify existing.txt is shown
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return true end
    end
    return false
  ]]
  )

  -- Externally create a new file (from outer Neovim)
  local new_path = tmp .. "/new_file.txt"
  vim.fn.writefile({ "new content" }, new_path)

  -- Press <C-l> to refresh
  e2e.feed(child, "<C-l>")

  -- Wait for new file to appear in the buffer
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("new_file.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["refresh"]["reflects externally deleted file after Ctrl-L"] = function()
  e2e.open_eda(child, tmp)

  -- Verify existing.txt is shown
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return true end
    end
    return false
  ]]
  )

  -- Externally delete the file
  vim.fn.delete(tmp .. "/existing.txt")

  -- Press <C-l> to refresh
  e2e.feed(child, "<C-l>")

  -- Wait for file to disappear from the buffer
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("existing.txt") then return false end
    end
    return true
  ]],
    10000
  )
end

local function intercept_watcher()
  e2e.exec(
    child,
    [[
    _G.watcher_callbacks = {}
    local Watcher = require("eda.watcher")
    local watch = Watcher.watch
    Watcher.watch = function(self, path, callback)
      _G.watcher_callbacks[path] = callback
      watch(self, path, function(...)
        _G.watcher_events = (_G.watcher_events or 0) + 1
        callback(...)
      end)
    end
  ]]
  )
end

local function delete_pending_line()
  e2e.exec(
    child,
    [[
    local ex = require("eda").get_current()
    _G.pending_id = ex.store:get_by_path(ex.root_path .. "/remove.txt").id
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      if line == "remove.txt" then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        vim.cmd.normal({ "dd", bang = true })
        break
      end
    end
  ]]
  )
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)
end

for _, event in ipairs({ "create", "rename", "delete" }) do
  T["refresh"]["preserves pending deletion during external " .. event] = function()
    e2e.create_file(tmp .. "/remove.txt", "remove me")
    intercept_watcher()
    e2e.open_eda(child, tmp)
    delete_pending_line()
    if event == "create" then
      e2e.create_file(tmp .. "/external.txt", "external")
    elseif event == "rename" then
      assert(vim.uv.fs_rename(tmp .. "/existing.txt", tmp .. "/external.txt"))
    else
      assert(vim.uv.fs_unlink(tmp .. "/existing.txt"))
    end
    e2e.wait_until(child, "(_G.watcher_events or 0) > 0")
    e2e.wait_until(
      child,
      [[
      local ex = require("eda").get_current()
      return ex.scanner._active_fds == 0
    ]]
    )
    MiniTest.expect.equality(
      e2e.exec(
        child,
        [[
      local ex = require("eda").get_current()
      return ex.store:get(_G.pending_id) ~= nil and vim.bo.modified
    ]]
      ),
      true
    )
    e2e.feed(child, ":w<CR>")
    e2e.wait_until(
      child,
      [[
      local ex = require("eda").get_current()
      return not vim.bo.modified and not vim.uv.fs_stat(ex.root_path .. "/remove.txt")
    ]]
    )
    e2e.wait_until(
      child,
      string.format(
        [[
      local ex = require("eda").get_current()
      local external = ex.store:get_by_path(ex.root_path .. "/external.txt")
      local existing = ex.store:get_by_path(ex.root_path .. "/existing.txt")
      return %s
    ]],
        event == "create" and "external ~= nil and existing ~= nil"
          or event == "rename" and "external ~= nil and existing == nil"
          or "external == nil and existing == nil"
      )
    )
  end
end

local function hold_background_scan(filename)
  child.lua("_G.refresh_filename = ...", { filename })
  e2e.exec(
    child,
    [[
    local ex = require("eda").get_current()
    ex.watcher:unwatch_all()
    local Scanner = require("eda.tree.scanner")
    local scan = Scanner.scan
    Scanner.scan = function(self, id, callback)
      return scan(self, id, function(err)
        callback(err)
        if self == _G.held_scanner then
          _G.finished_scans = (_G.finished_scans or 0) + 1
        end
      end)
    end
    local readdir = vim.uv.fs_readdir
    vim.uv.fs_readdir = function(dir, callback)
      return readdir(dir, function(err, entries)
        if not entries and not _G.release_scan then
          _G.held_scanner = ex.refresh._scanner
          _G.release_scan = function()
            vim.uv.fs_readdir = readdir
            callback(err, entries)
          end
        else
          callback(err, entries)
        end
      end)
    end
    _G.watcher_callbacks[ex.root_path](_G.refresh_filename)
  ]]
  )
  e2e.wait_until(child, "_G.release_scan ~= nil")
end

T["refresh"]["defers a scan that completes after editing begins"] = function()
  e2e.create_file(tmp .. "/remove.txt", "remove me")
  intercept_watcher()
  e2e.open_eda(child, tmp)
  hold_background_scan()
  delete_pending_line()
  e2e.exec(child, "_G.release_scan()")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return ex.scanner._active_fds == 0 and (not ex.refresh or not ex.refresh.running)
  ]]
  )
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    return ex.store:get(_G.pending_id) ~= nil and vim.bo.modified
  ]]
    ),
    true
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not vim.uv.fs_stat(ex.root_path .. "/remove.txt")
  ]]
  )
end

T["refresh"]["reconciles a deferred event after undo discards edits"] = function()
  e2e.create_file(tmp .. "/remove.txt", "remove me")
  intercept_watcher()
  e2e.exec(
    child,
    [[
    local create_autocmd = vim.api.nvim_create_autocmd
    vim.api.nvim_create_autocmd = function(event, opts)
      assert(event ~= "BufModifiedSet", "BufModifiedSet is unavailable")
      return create_autocmd(event, opts)
    end
  ]]
  )
  e2e.open_eda(child, tmp)
  delete_pending_line()
  e2e.create_file(tmp .. "/external.txt", "external")
  e2e.wait_until(child, "(_G.watcher_events or 0) > 0")
  e2e.feed(child, "u")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and ex.store:get_by_path(ex.root_path .. "/external.txt") ~= nil
      and not ex.refresh.pending and not ex.refresh.running
  ]]
  )
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/remove.txt"), { "remove me" })
end

T["refresh"]["retains the edit when its source is deleted externally"] = function()
  e2e.create_file(tmp .. "/remove.txt", "remove me")
  intercept_watcher()
  e2e.open_eda(child, tmp)
  e2e.exec(
    child,
    [[
    for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line == "remove.txt" then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "cc")
  e2e.feed_insert(child, "renamed.txt")
  assert(vim.uv.fs_unlink(tmp .. "/remove.txt"))
  e2e.wait_until(child, "(_G.watcher_events or 0) > 0")
  e2e.exec(
    child,
    [[
    _G.write_finished = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "EdaMutationPost",
      once = true,
      callback = function(args) _G.write_finished = args.data.results.error ~= nil end,
    })
  ]]
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "_G.write_finished")
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)
end

T["refresh"]["refresh_all preserves edits in an explorer"] = function()
  e2e.create_file(tmp .. "/remove.txt", "remove me")
  e2e.open_eda(child, tmp)
  delete_pending_line()
  e2e.exec(child, "require('eda').refresh_all()")
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    return ex.refresh.pending and ex.store:get(_G.pending_id) ~= nil
  ]]
    ),
    true
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not vim.uv.fs_stat(ex.root_path .. "/remove.txt")
  ]]
  )
end

T["refresh"]["coalesces watcher events raised during a save"] = function()
  e2e.create_file(tmp .. "/remove.txt", "remove me")
  intercept_watcher()
  e2e.open_eda(child, tmp)
  delete_pending_line()
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    local execute = Fs.execute_operations
    Fs.execute_operations = function(ops, opts, callback)
      _G.finish_write = function() execute(ops, opts, callback) end
    end
  ]]
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "_G.finish_write ~= nil")
  e2e.create_file(tmp .. "/external.txt", "external")
  e2e.wait_until(child, "(_G.watcher_events or 0) > 0")
  e2e.exec(child, "_G.finish_write()")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not ex.refresh.pending and not ex.refresh.running
      and ex.store:get_by_path(ex.root_path .. "/external.txt") ~= nil
      and not vim.uv.fs_stat(ex.root_path .. "/remove.txt")
  ]]
  )
end

for _, mode in ipairs({ "full", "scoped" }) do
  T["refresh"]["ignores a " .. mode .. " background scan completed after close"] = function()
    intercept_watcher()
    e2e.open_eda(child, tmp)
    hold_background_scan(mode == "scoped" and "existing.txt" or nil)
    e2e.exec(
      child,
      [[
    _G.closed_explorer = require("eda").get_current()
    _G.closed_nodes = _G.closed_explorer.store.nodes
    require("eda").close()
    _G.release_scan()
  ]]
    )
    e2e.wait_until(child, "(_G.finished_scans or 0) > 0")
    MiniTest.expect.equality(
      e2e.exec(
        child,
        [[
    return require("eda").get_current() == nil and _G.closed_explorer.store.nodes == _G.closed_nodes
  ]]
      ),
      true
    )
  end
end

T["refresh"]["ignores old root callbacks and installs a guarded new root watcher"] = function()
  e2e.create_file(tmp .. "/nested/keep.txt", "keep")
  e2e.create_file(tmp .. "/nested/remove.txt", "remove me")
  intercept_watcher()
  e2e.open_eda(child, tmp)
  hold_background_scan()
  e2e.exec(
    child,
    [[
    local eda = require("eda")
    local ex = eda.get_current()
    _G.old_root = ex.root_path
    eda._change_root(ex, ex.root_path .. "/nested")
  ]]
  )
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return ex._initial_scan_complete and _G.watcher_callbacks[ex.root_path] ~= nil
  ]]
  )
  e2e.exec(
    child,
    [[
    _G.release_scan()
    _G.watcher_callbacks[_G.old_root]()
  ]]
  )
  e2e.wait_until(child, "(_G.finished_scans or 0) > 0")
  delete_pending_line()
  e2e.create_file(tmp .. "/nested/external.txt", "external")
  e2e.wait_until(child, "(_G.watcher_events or 0) > 0")
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(
    child,
    [[
    local ex = require("eda").get_current()
    return not vim.bo.modified and not ex.refresh.pending and not ex.refresh.running
      and ex.store:get_by_path(ex.root_path .. "/external.txt") ~= nil
      and not vim.uv.fs_stat(ex.root_path .. "/remove.txt")
  ]]
  )
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/existing.txt"), { "exists" })
end

T["refresh"]["releases watchers when the explorer buffer is wiped"] = function()
  e2e.open_eda(child, tmp)
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = require("eda").get_current()
    local watched = next(ex.watcher._handles) ~= nil
    vim.api.nvim_buf_delete(ex.buffer.bufnr, { force = true })
    return watched and next(ex.watcher._handles) == nil
  ]]
    ),
    true
  )
end

return T
