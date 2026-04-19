local DirSize = require("eda.buffer.dir_size")
local helpers = require("helpers")

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      DirSize.setup({ cache_ttl_ms = 30000 })
      DirSize._clear_cache()
    end,
  },
})

T["ensure returns computing on cache miss, then populates cache"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/a.txt", "hello") -- 5 bytes
  helpers.create_file(tmp .. "/b.txt", "world!!") -- 7 bytes

  local r1 = DirSize.ensure(tmp)
  MiniTest.expect.equality(r1.state, "computing")

  local final
  helpers.wait_for(2000, function()
    final = DirSize.ensure(tmp)
    return final.state == "cached"
  end)
  MiniTest.expect.equality(final.state, "cached")
  MiniTest.expect.equality(final.bytes, 12)

  helpers.remove_temp_dir(tmp)
end

T["ensure walks nested directories and sums all descendant file sizes"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/sub")
  helpers.create_dir(tmp .. "/sub/deep")
  helpers.create_file(tmp .. "/a.txt", "aaaa") -- 4
  helpers.create_file(tmp .. "/sub/b.txt", "bbbbbbbb") -- 8
  helpers.create_file(tmp .. "/sub/deep/c.txt", "cccccccccccc") -- 12

  DirSize.ensure(tmp)
  local final
  helpers.wait_for(2000, function()
    final = DirSize.ensure(tmp)
    return final.state == "cached"
  end)
  MiniTest.expect.equality(final.state, "cached")
  MiniTest.expect.equality(final.bytes, 24)

  helpers.remove_temp_dir(tmp)
end

T["ensure returns cached within TTL without relaunching walk"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/a.txt", "hi")

  DirSize.ensure(tmp)
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)

  local call_count = 0
  local orig = DirSize._start_walk
  DirSize._start_walk = function(p)
    call_count = call_count + 1
    orig(p)
  end

  local r = DirSize.ensure(tmp)
  MiniTest.expect.equality(r.state, "cached")
  MiniTest.expect.equality(call_count, 0)

  DirSize._start_walk = orig
  helpers.remove_temp_dir(tmp)
end

T["ensure re-launches walk after TTL expiry"] = function()
  DirSize.setup({ cache_ttl_ms = 20 })
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/a.txt", "hi")

  DirSize.ensure(tmp)
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)
  vim.uv.sleep(60)

  local call_count = 0
  local orig = DirSize._start_walk
  DirSize._start_walk = function(p)
    call_count = call_count + 1
    orig(p)
  end

  local r = DirSize.ensure(tmp)
  MiniTest.expect.equality(r.state, "computing")
  MiniTest.expect.equality(call_count, 1)

  DirSize._start_walk = orig
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)
  helpers.remove_temp_dir(tmp)
end

T["dedup: second ensure while walking does not relaunch"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/a.txt", "hi")

  local call_count = 0
  local orig = DirSize._start_walk
  DirSize._start_walk = function(p)
    call_count = call_count + 1
    orig(p)
  end

  local r1 = DirSize.ensure(tmp)
  local r2 = DirSize.ensure(tmp)
  MiniTest.expect.equality(r1.state, "computing")
  MiniTest.expect.equality(r2.state, "computing")
  MiniTest.expect.equality(call_count, 1)

  DirSize._start_walk = orig
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)
  helpers.remove_temp_dir(tmp)
end

T["symlink entry counted as link-own size, target not followed"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/target")
  helpers.create_file(tmp .. "/target/big.bin", string.rep("x", 10000)) -- 10000 bytes

  local ok = pcall(vim.uv.fs_symlink, tmp .. "/target", tmp .. "/link")
  if not ok then
    return
  end

  DirSize.ensure(tmp)
  local final
  helpers.wait_for(2000, function()
    final = DirSize.ensure(tmp)
    return final.state == "cached"
  end)
  MiniTest.expect.equality(final.state, "cached")
  -- If link were followed: 10000 (target real) + 10000 (via link) + link lstat size = 20000+.
  -- Link NOT followed: 10000 (target/big.bin) + link's own lstat size (a few dozen bytes).
  MiniTest.expect.equality(final.bytes >= 10000, true)
  MiniTest.expect.equality(final.bytes < 15000, true)

  helpers.remove_temp_dir(tmp)
end

T["root opendir error: no cache written, retry is allowed"] = function()
  local nonexistent = "/tmp/dir_size_nonexistent_" .. tostring(vim.uv.hrtime())
  local r = DirSize.ensure(nonexistent)
  MiniTest.expect.equality(r.state, "computing")

  helpers.wait_for(1000, function()
    return not DirSize.is_computing()
  end)

  local call_count = 0
  local orig = DirSize._start_walk
  DirSize._start_walk = function(p)
    call_count = call_count + 1
    orig(p)
  end

  local r2 = DirSize.ensure(nonexistent)
  MiniTest.expect.equality(r2.state, "computing")
  MiniTest.expect.equality(call_count, 1)

  DirSize._start_walk = orig
  helpers.wait_for(1000, function()
    return not DirSize.is_computing()
  end)
end

T["_clear_cache empties cache; subsequent ensure on same path relaunches walk"] = function()
  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/a.txt", "hi")

  DirSize.ensure(tmp)
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)

  DirSize._clear_cache()

  local call_count = 0
  local orig = DirSize._start_walk
  DirSize._start_walk = function(p)
    call_count = call_count + 1
    orig(p)
  end

  local r = DirSize.ensure(tmp)
  MiniTest.expect.equality(r.state, "computing")
  MiniTest.expect.equality(call_count, 1)

  DirSize._start_walk = orig
  helpers.wait_for(2000, function()
    return DirSize.ensure(tmp).state == "cached"
  end)
  helpers.remove_temp_dir(tmp)
end

return T
