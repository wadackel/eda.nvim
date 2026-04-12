local action = require("eda.action")

-- Ensure builtin actions are loaded
require("eda.action.builtin")

local T = MiniTest.new_set()

T["register and dispatch"] = function()
  local called = false
  action.register("test_action", function()
    called = true
  end)
  action.dispatch("test_action", {})
  MiniTest.expect.equality(called, true)
end

T["register with desc stores metadata"] = function()
  action.register("test_with_desc", function() end, { desc = "Test description" })
  local entry = action.get_entry("test_with_desc")
  MiniTest.expect.equality(entry ~= nil, true)
  MiniTest.expect.equality(entry.desc, "Test description")
end

T["register without desc stores nil desc"] = function()
  action.register("test_no_desc", function() end)
  local entry = action.get_entry("test_no_desc")
  MiniTest.expect.equality(entry ~= nil, true)
  MiniTest.expect.equality(entry.desc, nil)
end

T["get_entry returns entry with fn and desc"] = function()
  local fn = function() end
  action.register("test_entry", fn, { desc = "Entry test" })
  local entry = action.get_entry("test_entry")
  MiniTest.expect.equality(entry.fn, fn)
  MiniTest.expect.equality(entry.desc, "Entry test")
end

T["get_entry returns nil for unknown action"] = function()
  local entry = action.get_entry("nonexistent_entry_xyz")
  MiniTest.expect.equality(entry, nil)
end

T["get returns function for action with desc"] = function()
  local fn = function() end
  action.register("test_get_compat", fn, { desc = "Compat test" })
  local result = action.get("test_get_compat")
  MiniTest.expect.equality(result, fn)
end

T["list returns registered action names"] = function()
  local names = action.list()
  MiniTest.expect.equality(type(names), "table")
  -- Should contain builtin actions
  local has_select = vim.tbl_contains(names, "select")
  local has_close = vim.tbl_contains(names, "close")
  MiniTest.expect.equality(has_select, true)
  MiniTest.expect.equality(has_close, true)
end

T["get returns registered action"] = function()
  local fn = action.get("select")
  MiniTest.expect.equality(type(fn), "function")
end

T["get returns nil for unknown action"] = function()
  local fn = action.get("nonexistent_action_xyz")
  MiniTest.expect.equality(fn, nil)
end

T["dispatch does nothing for unknown action"] = function()
  -- Should not error
  action.dispatch("nonexistent_action_xyz", {})
end

T["dispatch works with new registry structure"] = function()
  local value = 0
  action.register("test_dispatch_new", function()
    value = 42
  end, { desc = "Dispatch test" })
  action.dispatch("test_dispatch_new", {})
  MiniTest.expect.equality(value, 42)
end

T["builtin actions registered"] = function()
  local expected = {
    "actions",
    "select",
    "select_split",
    "select_vsplit",
    "select_tab",
    "close",
    "parent",
    "cwd",
    "cd",
    "collapse_all",
    "collapse_node",
    "refresh",
    "toggle_hidden",
    "yank_path",
    "yank_path_absolute",
    "yank_name",
    "cut",
    "copy",
    "paste",
    "split",
    "toggle_gitignored",
    "expand_recursive",
    "collapse_recursive",
  }
  for _, name in ipairs(expected) do
    MiniTest.expect.equality(action.get(name) ~= nil, true)
  end
end

T["builtin actions have descriptions"] = function()
  local names = action.list()
  for _, name in ipairs(names) do
    local entry = action.get_entry(name)
    -- All builtin actions should have a desc (test_* actions may not)
    if not name:match("^test_") then
      MiniTest.expect.equality(entry.desc ~= nil, true)
    end
  end
end

return T
