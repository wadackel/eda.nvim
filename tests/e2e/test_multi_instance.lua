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

local child_a, child_b, shared_tmp

T["cross-process swap conflict"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      shared_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(shared_tmp .. "/file.txt", "hello")
      child_a = e2e.spawn()
      e2e.setup_eda(child_a)
      child_b = e2e.spawn()
      e2e.setup_eda(child_b)
    end,
    post_case = function()
      e2e.stop(child_a)
      e2e.stop(child_b)
      e2e.remove_temp_dir(shared_tmp)
    end,
  },
})

T["cross-process swap conflict"]["two child neovims open eda in the same directory without swap conflict"] = function()
  -- child_a opens eda first; without the fix this creates a swap file at
  -- ~/.local/state/nvim/swap/eda:%%%<encoded-path>.swp.
  e2e.open_eda(child_a, shared_tmp)

  -- child_b opens eda in the same directory while child_a is still alive.
  -- Without the fix, nvim_buf_set_name triggers swap-file detection and raises
  -- E325 ATTENTION (which can surface to the user as E95 after the dialog flow).
  e2e.open_eda(child_b, shared_tmp)

  -- Both children must end up with a valid eda buffer and swapfile disabled.
  local a_swap = e2e.exec(child_a, "return vim.bo[require('eda').get_current().buffer.bufnr].swapfile")
  local b_swap = e2e.exec(child_b, "return vim.bo[require('eda').get_current().buffer.bufnr].swapfile")
  MiniTest.expect.equality(a_swap, false)
  MiniTest.expect.equality(b_swap, false)

  local a_ft = e2e.exec(child_a, "return vim.bo[require('eda').get_current().buffer.bufnr].filetype")
  local b_ft = e2e.exec(child_b, "return vim.bo[require('eda').get_current().buffer.bufnr].filetype")
  MiniTest.expect.equality(a_ft, "eda")
  MiniTest.expect.equality(b_ft, "eda")
end

return T
