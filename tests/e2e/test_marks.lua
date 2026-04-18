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

T["marks"]["delete action rescans tree on partial failure and clears only completed marks"] = function()
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
      delete_to_trash = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("delete") ~= nil'), true)

  -- Mark a.txt and b.txt
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")
  e2e.feed(child, "m")

  -- Monkey-patch execute_operations: a.txt succeeds, b.txt fails (simulated partial failure)
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    Fs.execute_operations = function(ops, opts, cb)
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

  e2e.feed(child, "D")

  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  e2e.feed(child, "y")

  -- a.txt deleted (successful op); b.txt survives (failure); c.txt untouched (unmarked)
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/b.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/c.txt"), 1)

  -- Rescan must reflect a.txt deletion even on partial failure
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

  -- Mark bookkeeping: b.txt mark survives (failed op), a.txt's mark is cleared with it
  local b_still_marked = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node.name == "b.txt" and node._marked then return true end
    end
    return false
  ]]
  )
  MiniTest.expect.equality(b_still_marked, true)
end

T["marks"]["delete action deletes marked nodes after confirm"] = function()
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
      delete_to_trash = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Guard: `delete` action must be registered (not just mark_bulk_delete masquerading)
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("delete") ~= nil'), true)

  -- Mark a.txt then b.txt
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")
  e2e.feed(child, "m")

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

  -- Press D (now routed to delete action)
  e2e.feed(child, "D")

  e2e.wait_until(
    child,
    [[
    local buf = vim.api.nvim_get_current_buf()
    return vim.bo[buf].filetype == "eda_confirm"
  ]]
  )

  e2e.feed(child, "y")

  -- Both marked files should be deleted, c.txt remains
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/b.txt"), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/c.txt"), 1)

  -- All marks should be cleared (success path)
  local mark_info = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local marked = {}
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then table.insert(marked, node.name .. "/" .. node.id) end
    end
    return table.concat(marked, ",")
  ]]
  )
  MiniTest.expect.equality(mark_info, "")
end

T["marks"]["delete action deletes cursor node when no marks"] = function()
  -- Default setup: confirm = false (skips dialog)
  e2e.open_eda(child, tmp)

  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("delete") ~= nil'), true)

  -- No marks, cursor on a.txt
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "D")

  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/b.txt"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/c.txt"), 1)
end

T["marks"]["delete action deletes hidden marked file"] = function()
  e2e.create_file(tmp .. "/.hidden", "h")

  e2e.stop(child)
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_hidden = true,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("delete") ~= nil'), true)

  -- Locate the line for .hidden and mark it
  e2e.exec(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local header_lines = buf.painter.header_lines or 0
    for i, fl in ipairs(buf.flat_lines) do
      if fl.node.name == ".hidden" then
        vim.api.nvim_win_set_cursor(0, { i + header_lines, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "m")

  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node.name == ".hidden" and node._marked then return true end
    end
    return false
  ]]
  )

  e2e.feed(child, "D")

  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/.hidden"), 10000)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/a.txt"), 1)
end

T["marks"]["delete action skips dialog when confirm.delete is false"] = function()
  e2e.stop(child)
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = { delete = false, move = false, create = false },
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("delete") ~= nil'), true)

  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then return true end
    end
    return false
  ]]
  )

  e2e.feed(child, "D")

  -- No confirm dialog should appear; file should be deleted directly
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil", tmp .. "/a.txt"), 10000)

  -- Current filetype must never have been "eda_confirm"
  local ft = e2e.exec(child, "return vim.bo[vim.api.nvim_get_current_buf()].filetype")
  MiniTest.expect.equality(ft ~= "eda_confirm", true)
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

-- ===============================================================
-- A3: mark-aware cut / copy / duplicate + paste flow + Visual priority
-- ===============================================================

-- Mark the first 3 files (a.txt / b.txt / c.txt) by pressing `m` three times starting from line 1.
-- Cursor auto-advances after each mark, so after 3 presses it's at line 4 (empty beyond c.txt).
local function mark_first_three(c)
  e2e.exec(c, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(c, "m")
  e2e.feed(c, "m")
  e2e.feed(c, "m")
  e2e.wait_until(
    c,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count == 3
  ]]
  )
end

T["marks"]["cut action cuts all marked nodes and clears marks"] = function()
  e2e.open_eda(child, tmp)
  mark_first_three(child)

  e2e.feed(child, "gx")

  -- Wait for register to contain 3 paths
  e2e.wait_until(
    child,
    [[
    local reg = require("eda.register").get()
    return reg ~= nil and reg.operation == "cut" and #reg.paths == 3
  ]]
  )

  -- Marks should be cleared after cut (mark-originated)
  local mark_count = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count
  ]]
  )
  MiniTest.expect.equality(mark_count, 0)
end

T["marks"]["copy action copies all marked nodes and clears marks"] = function()
  e2e.open_eda(child, tmp)
  mark_first_three(child)

  e2e.feed(child, "gy")

  e2e.wait_until(
    child,
    [[
    local reg = require("eda.register").get()
    return reg ~= nil and reg.operation == "copy" and #reg.paths == 3
  ]]
  )

  local mark_count = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count
  ]]
  )
  MiniTest.expect.equality(mark_count, 0)
end

T["marks"]["duplicate action duplicates all marked nodes with _copy suffix"] = function()
  e2e.open_eda(child, tmp)
  mark_first_three(child)

  e2e.feed(child, "gd")

  -- Wait for 3 *_copy files to appear
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/a_copy.txt"), 10000)
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/b_copy.txt"), 10000)
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/c_copy.txt"), 10000)

  -- Marks cleared
  local mark_count = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count
  ]]
  )
  MiniTest.expect.equality(mark_count, 0)
end

T["marks"]["duplicate action works on a directory (recursive copy)"] = function()
  -- Create a subdirectory with a nested file
  e2e.create_dir(tmp .. "/subdir")
  e2e.create_file(tmp .. "/subdir/inner.txt", "inner")

  e2e.open_eda(child, tmp)

  -- Locate subdir line and mark it
  e2e.exec(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local header_lines = buf.painter.header_lines or 0
    for i, fl in ipairs(buf.flat_lines) do
      if fl.node.name == "subdir" then
        vim.api.nvim_win_set_cursor(0, { i + header_lines, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "m")

  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node.name == "subdir" and node._marked then return true end
    end
    return false
  ]]
  )

  e2e.feed(child, "gd")

  -- Expect subdir_copy directory with nested file copied
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/subdir_copy"), 10000)
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/subdir_copy/inner.txt"), 10000)
end

T["marks"]["mark -> cut -> navigate -> paste moves marked files (mark_bulk_move replacement)"] = function()
  -- Create a dest dir to move marked files into
  e2e.create_dir(tmp .. "/dest")
  e2e.open_eda(child, tmp)

  -- Mark a.txt and b.txt (locate by name; tree may sort dirs first)
  e2e.exec(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local header_lines = buf.painter.header_lines or 0
    for i, fl in ipairs(buf.flat_lines) do
      if fl.node.name == "a.txt" then
        vim.api.nvim_win_set_cursor(0, { i + header_lines, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "m")
  e2e.feed(child, "m")
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if node._marked then count = count + 1 end
    end
    return count == 2
  ]]
  )

  e2e.feed(child, "gx")
  e2e.wait_until(
    child,
    [[
    local reg = require("eda.register").get()
    return reg ~= nil and reg.operation == "cut" and #reg.paths == 2
  ]]
  )

  -- Move cursor to dest directory line (it's added after the 3 files)
  e2e.exec(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local header_lines = buf.painter.header_lines or 0
    for i, fl in ipairs(buf.flat_lines) do
      if fl.node.name == "dest" then
        vim.api.nvim_win_set_cursor(0, { i + header_lines, 0 })
        break
      end
    end
  ]]
  )

  e2e.feed(child, "gp")

  -- Both files should end up under dest/
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/dest/a.txt"), 10000)
  e2e.wait_until(child, string.format("return vim.uv.fs_stat(%q) ~= nil", tmp .. "/dest/b.txt"), 10000)
  -- Original locations gone
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/a.txt"), nil)
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/b.txt"), nil)
end

T["marks"]["visual selection takes priority over marks in cut"] = function()
  e2e.open_eda(child, tmp)

  -- Mark c.txt only (line 3)
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {3, 0})")
  e2e.feed(child, "m")
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node.name == "c.txt" and node._marked then return true end
    end
    return false
  ]]
  )

  -- Enter Visual-line mode on lines 1-2 (a.txt, b.txt), then cut
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "Vj")
  -- Wait for visual mode to be active
  e2e.wait_until(child, 'return vim.fn.mode() == "V"')
  e2e.feed(child, "gx")

  -- Register should contain exactly the visual range (2 items), mark on c.txt preserved
  e2e.wait_until(
    child,
    [[
    local reg = require("eda.register").get()
    if not reg or reg.operation ~= "cut" or #reg.paths ~= 2 then return false end
    -- Paths must be a.txt and b.txt (visual range), not c.txt (marked)
    local basenames = {}
    for _, p in ipairs(reg.paths) do
      basenames[vim.fn.fnamemodify(p, ":t")] = true
    end
    return basenames["a.txt"] and basenames["b.txt"] and not basenames["c.txt"]
  ]]
  )

  -- c.txt mark should persist (visual-originated cut doesn't clear marks)
  local c_still_marked = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    for _, node in pairs(explorer.store.nodes) do
      if node.name == "c.txt" and node._marked then return true end
    end
    return false
  ]]
  )
  MiniTest.expect.equality(c_still_marked, true)
end

T["marks"]["quickfix action sends marked files to qflist and keeps marks"] = function()
  e2e.stop(child)
  child = e2e.spawn()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      quickfix = { auto_open = false },
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Guard: quickfix action must be registered
  MiniTest.expect.equality(e2e.exec(child, 'return require("eda.action").get_entry("quickfix") ~= nil'), true)

  -- Mark a.txt and b.txt (m advances the cursor each time)
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "m")
  e2e.feed(child, "m")

  e2e.wait_until(
    child,
    [[
    local buf = require("eda").get_current().buffer
    local count = 0
    for _, fl in ipairs(buf.flat_lines) do
      if fl.node._marked then count = count + 1 end
    end
    return count == 2
  ]]
  )

  -- Reset qflist so the populated-state assertion is unambiguous
  e2e.exec(child, 'vim.fn.setqflist({}, "f")')

  -- Fire quickfix action via its default keymap
  e2e.feed(child, "gq")

  -- Wait until qflist has the two marked files
  e2e.wait_until(child, "return #vim.fn.getqflist() == 2", 5000)

  -- Title check
  local title = e2e.exec(child, "return vim.fn.getqflist({ title = 0 }).title")
  MiniTest.expect.equality(title, "eda marks")

  -- Entries include a.txt and b.txt
  local has_files = e2e.exec(
    child,
    [[
    local items = vim.fn.getqflist()
    local basenames = {}
    for _, it in ipairs(items) do
      local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(it.bufnr), ":t")
      basenames[name] = true
    end
    return basenames["a.txt"] and basenames["b.txt"]
  ]]
  )
  MiniTest.expect.equality(has_files, true)

  -- Marks survive (quickfix is non-destructive)
  local marks_retained = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local count = 0
    for _, node in pairs(explorer.store.nodes) do
      if (node.name == "a.txt" or node.name == "b.txt") and node._marked then
        count = count + 1
      end
    end
    return count == 2
  ]]
  )
  MiniTest.expect.equality(marks_retained, true)

  -- Quickfix window must stay closed with auto_open = false
  local qf_winid = e2e.exec(child, "return vim.fn.getqflist({ winid = 0 }).winid")
  MiniTest.expect.equality(qf_winid, 0)
end

return T
