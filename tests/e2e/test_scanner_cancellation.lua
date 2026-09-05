local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/target", "target")
      e2e.create_dir(tmp .. "/new-root")
      e2e.create_file(tmp .. "/new-root/keep.txt", "keep")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})
for _, transition in ipairs({ "initial root change", "initial close", "refresh root change" }) do
  T[transition .. " cancels pending symlink metadata"] = function()
    if transition == "refresh root change" then
      e2e.open_eda(child, tmp)
    end
    e2e.exec(
      child,
      string.format(
        [[
      _G.metadata_root = %q
      _G.metadata_callbacks = {}
      local realpath = vim.uv.fs_realpath
      vim.uv.fs_realpath = function(path, callback)
        if callback and path:sub(1, #_G.metadata_root + 5) == _G.metadata_root .. "/link" then
          _G.metadata_callbacks[#_G.metadata_callbacks + 1] = callback
          return {}
        end
        return realpath(path, callback)
      end
    ]],
        tmp
      )
    )
    for i = 1, 50 do
      assert(vim.uv.fs_symlink(tmp .. "/target", tmp .. "/link" .. i))
    end
    e2e.exec(
      child,
      string.format(
        [[
      local eda = require("eda")
      if %q == "refresh root change" then
        eda.get_current().refresh:request(_G.metadata_root)
      else
        eda.open({ dir = _G.metadata_root })
      end
    ]],
        transition
      )
    )
    e2e.wait_until(child, "#_G.metadata_callbacks > 0")
    e2e.exec(
      child,
      string.format(
        [[
      local eda = require("eda")
      local ex = eda.get_current()
      _G.cancelled_scanner = %q == "refresh root change" and ex.refresh._scanner or ex.scanner
      assert(_G.cancelled_scanner)
      if %q == "initial close" then
        eda.close()
      else
        eda._change_root(ex, _G.metadata_root .. "/new-root")
      end
    ]],
        transition,
        transition
      )
    )
    MiniTest.expect.equality(e2e.exec(child, "return _G.cancelled_scanner._disposed"), true)
    if transition ~= "initial close" then
      e2e.wait_until(
        child,
        [[
        local ex = require("eda").get_current()
        return ex and ex.root_path == _G.metadata_root .. "/new-root" and ex._initial_scan_complete
      ]]
      )
      MiniTest.expect.equality(e2e.get_buf_lines(child), { "keep.txt" })
    end
    e2e.exec(
      child,
      [[
      for _, callback in ipairs(_G.metadata_callbacks) do callback(nil, _G.metadata_root .. "/target") end
    ]]
    )
    e2e.wait_until(child, "_G.cancelled_scanner._metadata._active == 0")
    MiniTest.expect.equality(e2e.exec(child, "return _G.cancelled_scanner._active_fds"), 0)
    MiniTest.expect.equality(e2e.exec(child, "return next(_G.cancelled_scanner._scanning) == nil"), true)
    if transition == "initial close" then
      MiniTest.expect.equality(e2e.exec(child, "return require('eda').get_current() == nil"), true)
    else
      MiniTest.expect.equality(e2e.get_buf_lines(child), { "keep.txt" })
    end
  end
end
return T
