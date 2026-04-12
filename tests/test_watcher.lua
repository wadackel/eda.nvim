local Watcher = require("eda.watcher")

local T = MiniTest.new_set()

T["new creates watcher"] = function()
  local w = Watcher.new()
  MiniTest.expect.equality(type(w), "table")
  MiniTest.expect.equality(type(w._handles), "table")
end

T["pending_operations management"] = function()
  local w = Watcher.new()
  w:add_pending("/tmp/test")
  MiniTest.expect.equality(w.pending_operations["/tmp/test"], true)
  w:remove_pending("/tmp/test")
  MiniTest.expect.equality(w.pending_operations["/tmp/test"], nil)
end

T["unwatch_all clears handles"] = function()
  local w = Watcher.new()
  w:unwatch_all() -- Should not error even with no watches
  MiniTest.expect.equality(next(w._handles), nil)
end

return T
