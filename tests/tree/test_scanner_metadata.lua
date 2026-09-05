local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local helpers = require("helpers")
local tmp, original_realpath, original_stat, scanners
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
      original_realpath, original_stat = vim.uv.fs_realpath, vim.uv.fs_stat
      scanners = {}
    end,
    post_case = function()
      vim.uv.fs_realpath, vim.uv.fs_stat = original_realpath, original_stat
      for _, scanner in ipairs(scanners) do
        if scanner.dispose then
          scanner:dispose()
        end
      end
      helpers.remove_temp_dir(tmp)
    end,
  },
})
local function scanner_for(path, follow)
  local store = Store.new()
  store:set_root(path)
  local scanner = Scanner.new(store, { follow_symlinks = follow })
  scanners[#scanners + 1] = scanner
  return scanner, store
end
local function scan(scanner, id)
  local done = false
  scanner:scan(id or scanner.store.root_id, function()
    done = true
  end)
  helpers.wait_for(3000, function()
    return done
  end)
  MiniTest.expect.equality(done, true)
end
for _, follow in ipairs({ false, true }) do
  T["resolves file, directory, and broken links asynchronously with follow=" .. tostring(follow)] = function()
    helpers.create_file(tmp .. "/file", "file")
    helpers.create_dir(tmp .. "/dir")
    for _, name in ipairs({ "file", "dir", "missing" }) do
      assert(vim.uv.fs_symlink(tmp .. "/" .. name, tmp .. "/link-" .. name))
    end
    local calls, sync_calls = 0, 0
    vim.uv.fs_realpath = function(path, callback)
      calls = calls + 1
      if not callback then
        sync_calls = sync_calls + 1
      end
      return original_realpath(path, callback)
    end
    vim.uv.fs_stat = function(path, callback)
      if not callback then
        sync_calls = sync_calls + 1
      end
      return original_stat(path, callback)
    end
    local scanner, store = scanner_for(tmp, follow)
    scan(scanner)
    MiniTest.expect.equality(sync_calls, 0)
    MiniTest.expect.equality(calls, 3)
    MiniTest.expect.equality(store:get_by_path(tmp .. "/link-file").type, "link")
    MiniTest.expect.equality(store:get_by_path(tmp .. "/link-dir").type, follow and "directory" or "link")
    MiniTest.expect.equality(store:get_by_path(tmp .. "/link-dir").link_target, tmp .. "/dir")
    MiniTest.expect.equality(store:get_by_path(tmp .. "/link-missing").link_broken, true)
    MiniTest.expect.equality(scanner._active_fds, 0)
  end
end
T["bounds pending metadata across directories and settles coalesced callers"] = function()
  helpers.create_file(tmp .. "/target", "target")
  for _, name in ipairs({ "a", "b" }) do
    helpers.create_dir(tmp .. "/" .. name)
    for i = 1, 50 do
      assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/" .. name .. "/link" .. i))
    end
  end
  local scanner, store = scanner_for(tmp, true)
  scan(scanner)
  local pending, active, peak, sync_calls = {}, 0, 0, 0
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      sync_calls = sync_calls + 1
      return original_realpath(path)
    end
    active = active + 1
    peak = math.max(peak, active)
    pending[#pending + 1] = function()
      active = active - 1
      callback(nil, tmp .. "/target")
    end
    return {}
  end
  local settled = 0
  for _, name in ipairs({ "a", "b", "a" }) do
    scanner:scan(store:get_by_path(tmp .. "/" .. name).id, function()
      settled = settled + 1
    end)
  end
  helpers.wait_for(3000, function()
    return #pending >= 32 or settled == 3
  end)
  MiniTest.expect.equality(sync_calls, 0)
  MiniTest.expect.equality(settled, 0)
  MiniTest.expect.equality(peak <= 32, true)
  for _ = 1, 10 do
    local batch = pending
    pending = {}
    for _, complete in ipairs(batch) do
      complete()
    end
    helpers.wait_for(3000, function()
      return #pending > 0 or settled == 3
    end)
    if settled == 3 then
      break
    end
  end
  MiniTest.expect.equality(settled, 3)
  MiniTest.expect.equality(peak <= 32, true)
  MiniTest.expect.equality(scanner._active_fds, 0)
  MiniTest.expect.equality(#store:children(store:get_by_path(tmp .. "/a").id), 50)
  MiniTest.expect.equality(#store:children(store:get_by_path(tmp .. "/b").id), 50)
end
T["disposal skips queued links and settles both scan callbacks exactly once"] = function()
  helpers.create_file(tmp .. "/target", "target")
  for i = 1, 80 do
    assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/link" .. i))
  end
  local pending, starts = {}, 0
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      return original_realpath(path)
    end
    starts = starts + 1
    pending[#pending + 1] = callback
    return {}
  end
  local scanner, store = scanner_for(tmp, true)
  local settled = 0
  scanner:scan(store.root_id, function()
    settled = settled + 1
  end)
  scanner:scan(store.root_id, function()
    settled = settled + 1
  end)
  helpers.wait_for(3000, function()
    return #pending > 0 or settled > 0
  end)
  MiniTest.expect.equality(settled, 0)
  scanner:dispose()
  helpers.wait_for(3000, function()
    return settled == 2
  end)
  local before = starts
  for _, complete in ipairs(pending) do
    complete(nil, tmp .. "/target")
  end
  helpers.wait_for(3000, function()
    return scanner._metadata._active == 0
  end)
  MiniTest.expect.equality(settled, 2)
  MiniTest.expect.equality(starts, before)
  MiniTest.expect.equality(#store:children(store.root_id), 0)
  MiniTest.expect.equality(scanner._active_fds, 0)
end
T["root replacement abandons pending results without populating the new root"] = function()
  helpers.create_file(tmp .. "/target", "target")
  assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/link"))
  helpers.create_dir(tmp .. "/new-root")
  local pending
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      return original_realpath(path)
    end
    pending = callback
    return {}
  end
  local scanner, store = scanner_for(tmp, true)
  local done = false
  scanner:scan(store.root_id, function()
    done = true
  end)
  helpers.wait_for(3000, function()
    return pending ~= nil or done
  end)
  MiniTest.expect.equality(done, false)
  store:set_root(tmp .. "/new-root")
  pending(nil, tmp .. "/target")
  helpers.wait_for(3000, function()
    return done
  end)
  MiniTest.expect.equality(#store:children(store.root_id), 0)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/link"), nil)
  MiniTest.expect.equality(scanner._active_fds, 0)
end
T["deleted targets and metadata submission failure settle without hanging"] = function()
  helpers.create_file(tmp .. "/target", "target")
  assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/link"))
  vim.uv.fs_stat = function(path, callback)
    if callback then
      return nil, "ENOENT"
    end
    return original_stat(path)
  end
  local scanner, store = scanner_for(tmp, true)
  scan(scanner)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/link").link_broken, true)
  MiniTest.expect.equality(scanner._active_fds, 0)
end
T["detects a target deleted after realpath completes"] = function()
  helpers.create_file(tmp .. "/target", "target")
  assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/link"))
  local pending
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      return original_realpath(path)
    end
    return original_realpath(path, function(err, target)
      pending = function()
        callback(err, target)
      end
    end)
  end
  local scanner, store = scanner_for(tmp, true)
  local done = false
  scanner:scan(store.root_id, function()
    done = true
  end)
  helpers.wait_for(3000, function()
    return pending ~= nil
  end)
  assert(vim.uv.fs_unlink(tmp .. "/target"))
  pending()
  helpers.wait_for(3000, function()
    return done
  end)
  local link = store:get_by_path(tmp .. "/link")
  MiniTest.expect.equality(link.link_broken, true)
  MiniTest.expect.equality(link.link_target, nil)
end
T["a queued directory removed from the store releases its scan slot"] = function()
  helpers.create_dir(tmp .. "/a")
  helpers.create_dir(tmp .. "/b")
  helpers.create_file(tmp .. "/target", "target")
  assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/a/link"))
  local scanner, store = scanner_for(tmp, true)
  scan(scanner)
  scanner._max_concurrent_fds = 1
  local pending
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      return original_realpath(path)
    end
    pending = callback
    return {}
  end
  local settled = 0
  local a, b = store:get_by_path(tmp .. "/a"), store:get_by_path(tmp .. "/b")
  scanner:scan(a.id, function()
    settled = settled + 1
  end)
  scanner:scan(b.id, function()
    settled = settled + 1
  end)
  helpers.wait_for(3000, function()
    return pending ~= nil
  end)
  store:remove(b.id)
  pending(nil, tmp .. "/target")
  helpers.wait_for(3000, function()
    return settled == 2
  end)
  MiniTest.expect.equality(scanner._active_fds, 0)
  MiniTest.expect.equality(#scanner._pending_scans, 0)
  MiniTest.expect.equality(next(scanner._scanning), nil)
end
T["queued scans keep the root identity from the original request"] = function()
  helpers.create_dir(tmp .. "/a")
  helpers.create_dir(tmp .. "/b")
  helpers.create_dir(tmp .. "/new-root")
  helpers.create_file(tmp .. "/target", "target")
  helpers.create_file(tmp .. "/b/unexpected", "unexpected")
  assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/a/link"))
  local scanner, store = scanner_for(tmp, true)
  scan(scanner)
  scanner._max_concurrent_fds = 1
  local pending
  vim.uv.fs_realpath = function(path, callback)
    if not callback then
      return original_realpath(path)
    end
    pending = callback
    return {}
  end
  local settled = 0
  scanner:scan(store:get_by_path(tmp .. "/a").id, function()
    settled = settled + 1
  end)
  scanner:scan(store:get_by_path(tmp .. "/b").id, function()
    settled = settled + 1
  end)
  helpers.wait_for(3000, function()
    return pending ~= nil
  end)
  store:set_root(tmp .. "/new-root")
  pending(nil, tmp .. "/target")
  helpers.wait_for(3000, function()
    return settled == 2
  end)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/b/unexpected"), nil)
  MiniTest.expect.equality(scanner._active_fds, 0)
end
return T
