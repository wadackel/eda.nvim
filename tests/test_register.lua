local register = require("eda.register")

local T = MiniTest.new_set()

T["set and get"] = function()
  register.set({ "/a", "/b" }, "cut")
  local reg = register.get()
  MiniTest.expect.equality(reg ~= nil, true)
  MiniTest.expect.equality(#reg.paths, 2)
  MiniTest.expect.equality(reg.paths[1], "/a")
  MiniTest.expect.equality(reg.paths[2], "/b")
  MiniTest.expect.equality(reg.operation, "cut")
  register.clear()
end

T["clear sets register to nil"] = function()
  register.set({ "/x" }, "copy")
  MiniTest.expect.equality(register.get() ~= nil, true)
  register.clear()
  MiniTest.expect.equality(register.get(), nil)
end

T["has returns true for registered path"] = function()
  register.set({ "/a", "/b" }, "cut")
  MiniTest.expect.equality(register.has("/a"), true)
  MiniTest.expect.equality(register.has("/b"), true)
  MiniTest.expect.equality(register.has("/c"), false)
  register.clear()
end

T["has returns false when register is empty"] = function()
  register.clear()
  MiniTest.expect.equality(register.has("/a"), false)
end

T["is_cut returns true for cut paths"] = function()
  register.set({ "/a", "/b" }, "cut")
  MiniTest.expect.equality(register.is_cut("/a"), true)
  MiniTest.expect.equality(register.is_cut("/b"), true)
  MiniTest.expect.equality(register.is_cut("/c"), false)
  register.clear()
end

T["is_cut returns false for copy paths"] = function()
  register.set({ "/a" }, "copy")
  MiniTest.expect.equality(register.is_cut("/a"), false)
  register.clear()
end

T["is_cut returns false when register is empty"] = function()
  register.clear()
  MiniTest.expect.equality(register.is_cut("/a"), false)
end

T["register is global across calls"] = function()
  register.set({ "/x" }, "copy")
  -- Simulate another call
  local reg = register.get()
  MiniTest.expect.equality(reg.paths[1], "/x")
  MiniTest.expect.equality(reg.operation, "copy")
  register.clear()
end

return T
