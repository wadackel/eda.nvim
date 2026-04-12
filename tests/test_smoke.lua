local T = MiniTest.new_set()

T["smoke test"] = function()
  MiniTest.expect.equality(1 + 1, 2)
end

T["eda module loads"] = function()
  local eda = require("eda")
  MiniTest.expect.equality(type(eda.setup), "function")
  MiniTest.expect.equality(type(eda.open), "function")
  MiniTest.expect.equality(type(eda.toggle), "function")
  MiniTest.expect.equality(type(eda.close), "function")
end

return T
