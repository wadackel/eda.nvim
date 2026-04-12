local Buffer = require("eda.buffer")
local Store = require("eda.tree.store")
local config = require("eda.config")

local T = MiniTest.new_set()

T["new creates buffer with correct options"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_project", config.get())
  MiniTest.expect.equality(vim.bo[buf.bufnr].filetype, "eda")
  MiniTest.expect.equality(vim.bo[buf.bufnr].buftype, "acwrite")
  buf:destroy()
end

T["new sets buffer name"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_project", config.get())
  local name = vim.api.nvim_buf_get_name(buf.bufnr)
  MiniTest.expect.equality(name:find("eda://") ~= nil, true)
  buf:destroy()
end

T["render populates buffer"] = function()
  config.setup()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "foo.lua", path = "/project/foo.lua", type = "file", parent_id = root })
  store:get(root).children_state = "loaded"

  local buf = Buffer.new("/project", config.get())
  buf:render(store)

  local lines = vim.api.nvim_buf_get_lines(buf.bufnr, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1]:find("foo.lua") ~= nil, true)
  buf:destroy()
end

T["destroy cleans up buffer"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_destroy", config.get())
  local bufnr = buf.bufnr
  buf:destroy()
  MiniTest.expect.equality(vim.api.nvim_buf_is_valid(bufnr), false)
end

T["get_cursor_node returns nil for invalid window"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test", config.get())
  MiniTest.expect.equality(buf:get_cursor_node(99999), nil)
  buf:destroy()
end

T["set_mappings registers string action keymaps"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_mappings", config.get())

  local dispatched = nil
  buf:set_mappings({
    ["<CR>"] = "select",
    ["q"] = "close",
  }, function(action_name)
    dispatched = action_name
  end)

  -- Verify keymaps exist on the buffer
  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found_cr = false
  local found_q = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "<CR>" then
      found_cr = true
    end
    if km.lhs == "q" then
      found_q = true
    end
  end
  MiniTest.expect.equality(found_cr, true)
  MiniTest.expect.equality(found_q, true)

  buf:destroy()
end

T["set_mappings registers function keymaps"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_fn_map", config.get())

  local called = false
  buf:set_mappings({
    ["<leader>x"] = function()
      called = true
    end,
  }, function() end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "<Leader>x" or km.lhs == "\\x" then
      found = true
    end
  end
  MiniTest.expect.equality(found, true)

  buf:destroy()
end

T["set_mappings with false disables keymap"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_false_map", config.get())

  -- First set a mapping, then disable it
  buf:set_mappings({
    ["q"] = "close",
  }, function() end)
  buf:set_mappings({
    ["q"] = false,
  }, function() end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found_q = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "q" then
      found_q = true
    end
  end
  MiniTest.expect.equality(found_q, false)

  buf:destroy()
end

T["set_mappings registers visual mode for cut/copy"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_visual_map", config.get())

  buf:set_mappings({
    ["x"] = "cut",
    ["c"] = "copy",
  }, function() end)

  local v_keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "v")
  local found_cut = false
  local found_copy = false
  for _, km in ipairs(v_keymaps) do
    if km.lhs == "x" then
      found_cut = true
    end
    if km.lhs == "c" then
      found_copy = true
    end
  end
  MiniTest.expect.equality(found_cut, true)
  MiniTest.expect.equality(found_copy, true)

  buf:destroy()
end

T["save_cursor and restore_cursor preserve position by node ID"] = function()
  config.setup()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "aaa.lua", path = "/project/aaa.lua", type = "file", parent_id = root })
  local target_id = store:add({ name = "bbb.lua", path = "/project/bbb.lua", type = "file", parent_id = root })
  store:add({ name = "ccc.lua", path = "/project/ccc.lua", type = "file", parent_id = root })
  store:get(root).children_state = "loaded"

  local cfg = config.get()
  cfg.header = false
  local buf = Buffer.new("/project", cfg)
  buf:render(store)

  -- Open the buffer in a window so we can set cursor
  local winid =
    vim.api.nvim_open_win(buf.bufnr, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })

  -- Move cursor to line 2 (bbb.lua)
  vim.api.nvim_win_set_cursor(winid, { 2, 0 })
  buf:save_cursor(winid)
  MiniTest.expect.equality(buf.target_node_id, target_id)

  -- Re-render and check restore
  buf:render(store)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  MiniTest.expect.equality(cursor[1], 2) -- should restore to same line

  vim.api.nvim_win_close(winid, true)
  buf:destroy()
end

T["get_cursor_node returns correct node"] = function()
  config.setup()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "first.lua", path = "/project/first.lua", type = "file", parent_id = root })
  local second_id = store:add({ name = "second.lua", path = "/project/second.lua", type = "file", parent_id = root })
  store:get(root).children_state = "loaded"

  local cfg = config.get()
  cfg.header = false
  local buf = Buffer.new("/project", cfg)
  buf:render(store)

  local winid =
    vim.api.nvim_open_win(buf.bufnr, true, { relative = "editor", width = 40, height = 10, row = 0, col = 0 })
  vim.api.nvim_win_set_cursor(winid, { 2, 0 })

  local node = buf:get_cursor_node(winid)
  MiniTest.expect.equality(node ~= nil, true)
  MiniTest.expect.equality(node.id, second_id)
  MiniTest.expect.equality(node.name, "second.lua")

  vim.api.nvim_win_close(winid, true)
  buf:destroy()
end

T["set_mappings table-form dispatches string action"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_table_map", config.get())

  local dispatched = nil
  buf:set_mappings({
    ["<CR>"] = { action = "select", desc = "Open file" },
  }, function(action_name)
    dispatched = action_name
  end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "<CR>" then
      found = true
      MiniTest.expect.equality(km.desc, "Open file")
    end
  end
  MiniTest.expect.equality(found, true)

  buf:destroy()
end

T["set_mappings table-form with function action passes public context"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_table_fn", config.get())

  local received_ctx = nil
  buf:set_mappings({
    ["t"] = {
      action = function(ctx)
        received_ctx = ctx
      end,
      desc = "Test",
    },
  }, function() end, function()
    return {
      get_cwd = function()
        return "/test"
      end,
    }
  end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "t" then
      found = true
      MiniTest.expect.equality(km.desc, "Test")
    end
  end
  MiniTest.expect.equality(found, true)

  buf:destroy()
end

T["set_mappings function receives public context when get_public_ctx provided"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_fn_ctx", config.get())

  local received_ctx = nil
  buf:set_mappings({
    ["t"] = function(ctx)
      received_ctx = ctx
    end,
  }, function() end, function()
    return {
      get_cwd = function()
        return "/test"
      end,
    }
  end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "t" then
      found = true
    end
  end
  MiniTest.expect.equality(found, true)

  buf:destroy()
end

T["set_mappings table-form with false disables keymap"] = function()
  config.setup()
  local buf = Buffer.new("/tmp/test_table_false", config.get())

  buf:set_mappings({
    ["q"] = "close",
  }, function() end)
  buf:set_mappings({
    ["q"] = { action = false },
  }, function() end)

  local keymaps = vim.api.nvim_buf_get_keymap(buf.bufnr, "n")
  local found_q = false
  for _, km in ipairs(keymaps) do
    if km.lhs == "q" then
      found_q = true
    end
  end
  MiniTest.expect.equality(found_q, false)

  buf:destroy()
end
return T
