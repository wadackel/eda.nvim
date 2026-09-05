local Watcher = require("eda.watcher")

local T = MiniTest.new_set()

T["new creates watcher"] = function()
  local w = Watcher.new()
  MiniTest.expect.equality(type(w), "table")
  MiniTest.expect.equality(type(w._handles), "table")
end

T["unwatch_all clears handles"] = function()
  local w = Watcher.new()
  w:unwatch_all() -- Should not error even with no watches
  MiniTest.expect.equality(next(w._handles), nil)
end

return T
