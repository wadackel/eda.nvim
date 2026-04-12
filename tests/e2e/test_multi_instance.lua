local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["multi instance"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["multi instance"]["split action creates two independent explorers"] = function()
  e2e.open_eda(child, tmp)

  -- Record initial instance count
  local instances_before = e2e.exec(child, "return #require('eda').get_all()")
  MiniTest.expect.equality(instances_before, 1)

  -- Dispatch the split action
  e2e.exec(
    child,
    [[
    local action = require("eda.action")
    local eda = require("eda")
    local explorer = eda.get_current()
    local ctx = {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = require("eda.config").get(),
      explorer = explorer,
    }
    action.dispatch("split", ctx)
  ]]
  )

  -- Wait for second instance to be created
  e2e.wait_until(child, "#require('eda').get_all() == 2", 10000)

  -- Both instances should have eda filetype buffers
  local both_eda = e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    for _, inst in ipairs(instances) do
      if vim.bo[inst.buffer.bufnr].filetype ~= "eda" then
        return false
      end
    end
    return true
  ]]
  )
  MiniTest.expect.equality(both_eda, true)
end

return T
