local util = require("eda.util")

local T = MiniTest.new_set()

T["debounce"] = MiniTest.new_set()

T["debounce"]["delays function call"] = function()
  local called = false
  local debounced = util.debounce(50, function()
    called = true
  end)
  debounced.call()
  MiniTest.expect.equality(called, false)
  vim.wait(200, function()
    return called
  end, 10)
  MiniTest.expect.equality(called, true)
  debounced.dispose()
end

T["debounce"]["only fires last call"] = function()
  local count = 0
  local debounced = util.debounce(50, function()
    count = count + 1
  end)
  debounced.call()
  debounced.call()
  debounced.call()
  vim.wait(200, function()
    return count > 0
  end, 10)
  MiniTest.expect.equality(count, 1)
  debounced.dispose()
end

T["is_valid_buf"] = MiniTest.new_set()

T["is_valid_buf"]["returns true for valid buffer"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  MiniTest.expect.equality(util.is_valid_buf(buf), true)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["is_valid_buf"]["returns false for deleted buffer"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_delete(buf, { force = true })
  MiniTest.expect.equality(util.is_valid_buf(buf), false)
end

T["is_valid_buf"]["returns false for nil"] = function()
  MiniTest.expect.equality(util.is_valid_buf(nil), false)
end

T["is_valid_win"] = MiniTest.new_set()

T["is_valid_win"]["returns true for current window"] = function()
  MiniTest.expect.equality(util.is_valid_win(vim.api.nvim_get_current_win()), true)
end

T["is_valid_win"]["returns false for nil"] = function()
  MiniTest.expect.equality(util.is_valid_win(nil), false)
end

T["nfc_normalize"] = MiniTest.new_set()

T["nfc_normalize"]["returns empty string for empty input"] = function()
  MiniTest.expect.equality(util.nfc_normalize(""), "")
end

T["nfc_normalize"]["returns ascii unchanged"] = function()
  MiniTest.expect.equality(util.nfc_normalize("hello.lua"), "hello.lua")
end

T["nfc_normalize"]["composes a decomposed character wherever it sits"] = function()
  if vim.uv.os_uname().sysname ~= "Darwin" then
    MiniTest.skip("normalization only runs on macOS")
  end
  local decomposed, composed = "e\204\129", "\195\169"
  MiniTest.expect.equality(util.nfc_normalize(decomposed .. "/a.txt"), composed .. "/a.txt")
  MiniTest.expect.equality(util.nfc_normalize("/a/" .. decomposed .. "/b"), "/a/" .. composed .. "/b")
  MiniTest.expect.equality(util.nfc_normalize("/a/caf" .. decomposed), "/a/caf" .. composed)
end

T["nfc_normalize"]["handles non-empty string"] = function()
  local input = "test.txt"
  local result = util.nfc_normalize(input)
  MiniTest.expect.equality(type(result), "string")
  MiniTest.expect.equality(#result > 0, true)
end

T["relpath returns the path below root"] = function()
  MiniTest.expect.equality(util.relpath("/p/lib", "/p/lib/core/y.lua"), "core/y.lua")
  MiniTest.expect.equality(util.relpath("/p/lib", "/p/lib"), "")
end

T["relpath treats the filesystem root as a single slash"] = function()
  MiniTest.expect.equality(util.relpath("/", "/usr/bin"), "usr/bin")
  MiniTest.expect.equality(util.relpath("/", "/"), "")
end

T["relpath rejects a sibling that merely shares the prefix"] = function()
  MiniTest.expect.equality(util.relpath("/p/lib", "/p/libs/core/x.lua"), nil)
  MiniTest.expect.equality(util.relpath("/p/lib", "/other"), nil)
  MiniTest.expect.equality(util.relpath("/a", "/"), nil)
end

T["relpath leaves shell metacharacters in names untouched"] = function()
  MiniTest.expect.equality(util.relpath("/p", "/p/$HOME"), "$HOME")
  MiniTest.expect.equality(util.relpath("/p", "/p/~/x"), "~/x")
end

T["joinpath keeps a single separator"] = function()
  MiniTest.expect.equality(util.joinpath("/p/lib", "core"), "/p/lib/core")
  MiniTest.expect.equality(util.joinpath("/", "usr"), "/usr")
  MiniTest.expect.equality(util.joinpath("/p", "a/b.txt"), "/p/a/b.txt")
end

return T
