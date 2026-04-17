local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child

T["bulk_operations"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
    end,
    post_case = function()
      e2e.stop(child)
    end,
  },
})

-- mark_bulk_delete and mark_bulk_move have been removed. Their functionality is
-- replaced by the unified `delete` action and the mark -> cut -> navigate -> paste
-- flow respectively. Verify the actions are no longer registered.

T["bulk_operations"]["mark_bulk_delete action is no longer registered"] = function()
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("mark_bulk_delete") == nil'), true)
end

T["bulk_operations"]["mark_bulk_move action is no longer registered"] = function()
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("mark_bulk_move") == nil'), true)
end

T["bulk_operations"]["default D keymap routes to delete (not mark_bulk_delete)"] = function()
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.config").get().mappings["D"]'), "delete")
end

return T
