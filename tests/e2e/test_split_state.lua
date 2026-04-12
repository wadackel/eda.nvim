local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["split state"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file_a.txt", "aaa")
      e2e.create_file(tmp .. "/file_b.txt", "bbb")
      e2e.create_dir(tmp .. "/subdir")
      e2e.create_file(tmp .. "/subdir/nested.txt", "nested")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

---Helper: dispatch split action in inner neovim.
local function dispatch_split(nvim)
  e2e.exec(
    nvim,
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
  e2e.wait_until(nvim, "#require('eda').get_all() >= 2", 10000)
end

T["split state"]["expand directory in one pane does not affect other"] = function()
  e2e.open_eda(child, tmp)
  dispatch_split(child)

  -- Focus the second instance (most recently created = last in list)
  e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    local inst = instances[#instances]
    vim.api.nvim_set_current_win(inst.window.winid)
  ]]
  )

  -- Expand subdir/ in the second pane
  e2e.exec(child, [[
    local eda = require("eda")
    local explorer = eda.get_current()
    local node = explorer.store:get_by_path(]] .. string.format("%q", tmp .. "/subdir") .. [[)
    if node then
      node.open = true
      explorer.scanner:scan(node.id, function()
        vim.schedule(function()
          explorer.buffer:render(explorer.store)
        end)
      end)
    end
  ]])

  -- Wait for the expanded pane to show nested.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("nested.txt") then return true end
    end
    return false
  ]]
  )

  -- Now check the first instance's buffer does NOT show nested.txt
  local first_has_nested = e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    local first = instances[1]
    local lines = vim.api.nvim_buf_get_lines(first.buffer.bufnr, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("nested.txt") then return true end
    end
    return false
  ]]
  )
  MiniTest.expect.equality(first_has_nested, false)
end

T["split state"]["cd in one pane keeps other pane root unchanged"] = function()
  e2e.open_eda(child, tmp)
  dispatch_split(child)

  -- Focus the second instance and cd into subdir
  e2e.exec(
    child,
    string.format(
      [[
    local instances = require("eda").get_all()
    local inst = instances[#instances]
    vim.api.nvim_set_current_win(inst.window.winid)
    require("eda")._change_root(inst, %q)
  ]],
      tmp .. "/subdir"
    )
  )

  -- Wait for second pane to show nested.txt as a direct entry
  e2e.wait_until(
    child,
    [[
    local instances = require("eda").get_all()
    local inst = instances[#instances]
    local lines = vim.api.nvim_buf_get_lines(inst.buffer.bufnr, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("nested.txt") then return true end
    end
    return false
  ]],
    10000
  )

  -- First pane should still have original root_path
  local first_root = e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    return instances[1].root_path
  ]]
  )
  MiniTest.expect.equality(first_root, tmp)
end

T["split state"]["split twice creates 3 panes"] = function()
  e2e.open_eda(child, tmp)
  dispatch_split(child)

  -- Focus a pane and split again
  e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    local inst = instances[#instances]
    vim.api.nvim_set_current_win(inst.window.winid)
  ]]
  )

  -- Dispatch another split
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

  e2e.wait_until(child, "#require('eda').get_all() == 3", 10000)

  local count = e2e.exec(child, "return #require('eda').get_all()")
  MiniTest.expect.equality(count, 3)
end

T["split state"]["_current follows focus changes between panes"] = function()
  e2e.open_eda(child, tmp)

  local first_id = e2e.exec(child, "return require('eda').get_current().instance_id")

  dispatch_split(child)

  -- After split, _current should be the new instance
  local second_id = e2e.exec(child, "return require('eda').get_current().instance_id")
  MiniTest.expect.equality(first_id ~= second_id, true)

  -- Switch focus to first instance's window
  e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    vim.api.nvim_set_current_win(instances[1].window.winid)
  ]]
  )

  -- Wait for BufEnter to fire and update _current
  e2e.wait_until(child, string.format("require('eda').get_current().instance_id == %d", first_id))

  local current_id = e2e.exec(child, "return require('eda').get_current().instance_id")
  MiniTest.expect.equality(current_id, first_id)
end

T["split state"]["file creation refreshes all panes via refresh_all"] = function()
  e2e.open_eda(child, tmp)
  dispatch_split(child)

  -- Create a new file on disk
  local new_path = tmp .. "/new_file.txt"
  e2e.create_file(new_path, "new content")

  -- Call refresh_all
  e2e.exec(child, "require('eda').refresh_all()")

  -- Wait for both panes to show the new file
  e2e.wait_until(
    child,
    [[
    local instances = require("eda").get_all()
    for _, inst in ipairs(instances) do
      local lines = vim.api.nvim_buf_get_lines(inst.buffer.bufnr, 0, -1, false)
      local found = false
      for _, l in ipairs(lines) do
        if l:find("new_file.txt") then found = true; break end
      end
      if not found then return false end
    end
    return true
  ]],
    10000
  )
end

T["split state"]["both panes have decoration caches after split"] = function()
  e2e.open_eda(child, tmp)
  dispatch_split(child)

  -- Wait for second instance to render
  e2e.wait_until(
    child,
    [[
    local instances = require("eda").get_all()
    local inst = instances[#instances]
    local lines = vim.api.nvim_buf_get_lines(inst.buffer.bufnr, 0, -1, false)
    return #lines > 0 and lines[1] ~= ""
  ]],
    10000
  )

  -- Verify both painters have populated decoration caches
  local result = e2e.exec(
    child,
    [[
    local instances = require("eda").get_all()
    local counts = {}
    for i, inst in ipairs(instances) do
      local count = 0
      for _ in pairs(inst.buffer.painter._decoration_cache) do
        count = count + 1
      end
      counts[i] = count
    end
    -- Also verify namespaces are independent
    local ns1 = instances[1].buffer.painter.ns_hl
    local ns2 = instances[#instances].buffer.painter.ns_hl
    return { cache1 = counts[1], cache2 = counts[#instances], ns_independent = ns1 ~= ns2 }
  ]]
  )

  MiniTest.expect.equality(result.cache1 > 0, true)
  MiniTest.expect.equality(result.cache2 > 0, true)
  MiniTest.expect.equality(result.ns_independent, true)
end

return T
