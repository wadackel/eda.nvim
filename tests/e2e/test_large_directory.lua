local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      for i = 1, 3 do
        e2e.create_file(tmp .. "/file" .. i, "file")
      end
      e2e.setup_eda(child)
      e2e.exec(
        child,
        [[
      require("eda.config").get().large_dir_threshold = 2
      _G.large_warnings, _G.scans = {}, 0
      vim.notify = function(message)
        if message:find("large_dir_threshold", 1, true) then
          table.insert(_G.large_warnings, message)
        end
      end
      local Scanner = require("eda.tree.scanner")
      local scan = Scanner.scan
      Scanner.scan = function(self, id, callback)
        return scan(self, id, function(...)
          _G.scans = _G.scans + 1
          callback(...)
        end)
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
T["watcher refreshes, manual refresh, and reopening warn once for the session"] = function()
  e2e.open_eda(child, tmp)
  e2e.wait_until(child, "#_G.large_warnings == 1")
  for i = 1, 2 do
    local path = tmp .. "/added" .. i
    e2e.create_file(path, "added")
    e2e.wait_for_path_in_snapshot(child, path)
    e2e.wait_until(
      child,
      [[
      local refresh = require("eda").get_current().refresh
      return not refresh.pending and not refresh.running
    ]]
    )
    MiniTest.expect.equality(e2e.exec(child, "return #_G.large_warnings"), 1)
  end
  local before = e2e.exec(child, "return _G.scans")
  e2e.exec(child, [[require("eda").refresh_all()]])
  e2e.wait_until(
    child,
    string.format(
      [[
    local refresh = require("eda").get_current().refresh
    return _G.scans > %d and not refresh.pending and not refresh.running
  ]],
      before
    )
  )
  e2e.exec(child, [[require("eda").close()]])
  e2e.open_eda(child, tmp)
  e2e.wait_for_path_in_snapshot(child, tmp .. "/added2")
  MiniTest.expect.equality(e2e.exec(child, "return #_G.large_warnings"), 1)
end
return T
