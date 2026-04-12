local eda = require("eda")

local T = MiniTest.new_set()

local defaults = { delete = true, move = "overwrite_only", create = false }

T["delete"] = MiniTest.new_set()

T["delete"]["confirms when delete=true and has delete op"] = function()
  local ops = { { type = "delete", src = "/tmp/a" } }
  MiniTest.expect.equality(eda._should_confirm(defaults, ops), true)
end

T["delete"]["skips when delete=false"] = function()
  local conf = { delete = false, move = "overwrite_only", create = false }
  local ops = { { type = "delete", src = "/tmp/a" } }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), false)
end

T["move"] = MiniTest.new_set()

T["move"]["confirms when move=true"] = function()
  local conf = { delete = true, move = true, create = false }
  local ops = { { type = "move", src = "/tmp/a", dst = "/tmp/nonexistent_dst_xyz" } }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), true)
end

T["move"]["skips when move=false"] = function()
  local conf = { delete = true, move = false, create = false }
  local ops = { { type = "move", src = "/tmp/a", dst = "/tmp/b" } }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), false)
end

T["move"]["overwrite_only confirms when dst exists"] = function()
  -- Create a temp file to use as existing dst
  local tmp = vim.fn.tempname()
  local f = io.open(tmp, "w")
  f:write("x")
  f:close()

  local ops = { { type = "move", src = "/tmp/a", dst = tmp } }
  local result = eda._should_confirm(defaults, ops)
  os.remove(tmp)
  MiniTest.expect.equality(result, true)
end

T["move"]["overwrite_only skips when dst does not exist"] = function()
  local ops = { { type = "move", src = "/tmp/a", dst = "/tmp/nonexistent_should_confirm_test" } }
  MiniTest.expect.equality(eda._should_confirm(defaults, ops), false)
end

T["create"] = MiniTest.new_set()

T["create"]["skips when create=false"] = function()
  local ops = { { type = "create", dst = "/tmp/a" } }
  MiniTest.expect.equality(eda._should_confirm(defaults, ops), false)
end

T["create"]["confirms when create=true"] = function()
  local conf = { delete = true, move = "overwrite_only", create = true }
  local ops = { { type = "create", dst = "/tmp/a" } }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), true)
end

T["create"]["threshold confirms when count exceeds N"] = function()
  local conf = { delete = true, move = "overwrite_only", create = 2 }
  local ops = {
    { type = "create", dst = "/tmp/a" },
    { type = "create", dst = "/tmp/b" },
    { type = "create", dst = "/tmp/c" },
  }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), true)
end

T["create"]["threshold skips when count equals N"] = function()
  local conf = { delete = true, move = "overwrite_only", create = 2 }
  local ops = {
    { type = "create", dst = "/tmp/a" },
    { type = "create", dst = "/tmp/b" },
  }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), false)
end

T["create"]["threshold skips when count below N"] = function()
  local conf = { delete = true, move = "overwrite_only", create = 5 }
  local ops = { { type = "create", dst = "/tmp/a" } }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), false)
end

T["mixed"] = MiniTest.new_set()

T["mixed"]["no operations returns false"] = function()
  MiniTest.expect.equality(eda._should_confirm(defaults, {}), false)
end

T["mixed"]["all disabled returns false for any ops"] = function()
  local conf = { delete = false, move = false, create = false }
  local ops = {
    { type = "delete", src = "/tmp/a" },
    { type = "move", src = "/tmp/b", dst = "/tmp/c" },
    { type = "create", dst = "/tmp/d" },
  }
  MiniTest.expect.equality(eda._should_confirm(conf, ops), false)
end

return T
