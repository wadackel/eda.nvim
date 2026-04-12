local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["marks"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/a.txt", "a")
      e2e.create_file(tmp .. "/b.txt", "b")
      e2e.create_file(tmp .. "/c.txt", "c")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["marks"]["mark_bulk_delete deletes marked nodes after confirm"] = function()
  -- Need confirm = true for bulk delete confirm dialog
  e2e.stop(child)
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = true,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Mark first file (a.txt) with m, cursor auto-advances
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")

  -- Mark second file (b.txt) with m
  e2e.feed(child, "m")

  -- Wait for marks to be applied (nvim_input is async)
  e2e.wait_until(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local count = 0
    for _, fl in ipairs(buf.flat_lines) do
      if fl.node._marked then count = count + 1 end
    end
    return count >= 2
  ]]
  )

  -- Press D for mark_bulk_delete
  e2e.feed(child, "D")

  -- Wait for confirm dialog
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Confirm with y
  e2e.feed(child, "y")

  -- Wait for files to be deleted
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/b.txt"), 10000)

  -- c.txt should still exist
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/c.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a.txt"), 0)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/b.txt"), 0)
end

T["marks"]["mark_bulk_delete rescans tree on partial failure"] = function()
  -- Re-spawn with confirm = true
  e2e.stop(child)
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = true,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Mark a.txt (cursor at line 1), cursor auto-advances
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")

  -- Mark b.txt (cursor at line 2), cursor auto-advances
  e2e.feed(child, "m")

  -- Monkey-patch execute_operations to simulate partial failure:
  -- Delete only the first operation, report error for the rest.
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    Fs.execute_operations = function(ops, opts, cb)
      -- Find a.txt operation and delete it; report error for the other
      local a_op, other_op
      for _, op in ipairs(ops) do
        if op.path:find("a.txt", 1, true) then
          a_op = op
        else
          other_op = op
        end
      end
      if a_op then
        vim.fs.rm(a_op.path, { force = true })
      end
      cb({ completed = { a_op or ops[1] }, failed = other_op, error = "Simulated partial failure" })
    end
  ]]
  )

  -- Wait for marks to be applied (nvim_input is async)
  e2e.wait_until(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local count = 0
    for _, fl in ipairs(buf.flat_lines) do
      if fl.node._marked then count = count + 1 end
    end
    return count >= 2
  ]]
  )

  -- Press D for mark_bulk_delete
  e2e.feed(child, "D")

  -- Wait for confirm dialog
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  -- Confirm with y
  e2e.feed(child, "y")

  -- a.txt should be deleted (the successful operation)
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)

  -- b.txt should still exist (simulated failure)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/b.txt"), 1)

  -- c.txt should still exist (not marked)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/c.txt"), 1)

  -- Tree should reflect the updated state (rescan happened even though partial failure).
  -- Wait until eda buffer no longer shows a.txt (deleted), but still shows b.txt and c.txt.
  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "eda" then return false end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local has_a = false
    local has_c = false
    for _, l in ipairs(lines) do
      if l:find("a.txt") then has_a = true end
      if l:find("c.txt") then has_c = true end
    end
    return not has_a and has_c
  ]],
    10000
  )
end

T["marks"]["mark toggle marks and unmarks a node"] = function()
  e2e.open_eda(child, tmp)

  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")

  -- Mark
  e2e.feed(child, "m")
  local marked = e2e.exec(
    child,
    [[
    local eda = require("eda")
    local explorer = eda.get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count
  ]]
  )
  MiniTest.expect.equality(marked, 1)

  -- Go back to the same node and unmark
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")
  local unmarked = e2e.exec(
    child,
    [[
    local eda = require("eda")
    local explorer = eda.get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count
  ]]
  )
  MiniTest.expect.equality(unmarked, 0)
end

return T
