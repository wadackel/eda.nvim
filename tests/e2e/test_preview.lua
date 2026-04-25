local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["preview"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/alpha.txt", "alpha content")
      e2e.create_file(tmp .. "/beta.txt", "beta content")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["preview"]["toggle_preview shows and hides preview window"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      preview = { enabled = false, debounce = 0 },
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  local win_count_before = e2e.get_win_count(child)

  -- Dispatch toggle_preview action
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
    action.dispatch("toggle_preview", ctx)
  ]]
  )

  -- Preview should add a window
  e2e.wait_until(child, string.format("#vim.api.nvim_list_wins() > %d", win_count_before), 5000)

  -- Toggle off
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
    action.dispatch("toggle_preview", ctx)
  ]]
  )

  -- Window count should return to before
  e2e.wait_until(child, string.format("#vim.api.nvim_list_wins() == %d", win_count_before), 5000)
end

T["preview"]["cursor move updates preview content"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      preview = { enabled = true, debounce = 0 },
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for preview window to appear (enabled = true)
  e2e.wait_until(child, "#vim.api.nvim_list_wins() >= 3", 5000)

  -- Move cursor to alpha.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("alpha.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Wait a bit for debounce and preview update
  e2e.wait_until(
    child,
    [[
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for _, l in ipairs(lines) do
        if l:find("alpha content") then return true end
      end
    end
    return false
  ]],
    5000
  )

  -- Move cursor to beta.txt
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("beta.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Preview should now show beta content
  e2e.wait_until(
    child,
    [[
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for _, l in ipairs(lines) do
        if l:find("beta content") then return true end
      end
    end
    return false
  ]],
    5000
  )
end

-- Directory preview tests
local dir_child, dir_tmp

T["dir_preview"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      dir_child = e2e.spawn()
      dir_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(dir_tmp .. "/sub")
      e2e.create_file(dir_tmp .. "/sub/x.txt", "hello dir preview")
      e2e.create_file(dir_tmp .. "/top.txt", "root level")
    end,
    post_case = function()
      e2e.stop(dir_child)
      e2e.remove_temp_dir(dir_tmp)
    end,
  },
})

T["dir_preview"]["PR-D-E1 cursor on closed dir shows children"] = function()
  e2e.exec(
    dir_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      preview = { enabled = true, debounce = 0 },
    })
  ]]
  )

  e2e.open_eda(dir_child, dir_tmp)

  -- Move cursor to the line containing "sub" (closed by default)
  e2e.wait_until(
    dir_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("sub", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Preview should appear and contain x.txt (1-level child of sub)
  e2e.wait_until(
    dir_child,
    [[
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for _, l in ipairs(lines) do
        if l:find("x.txt", 1, true) then return true end
      end
    end
    return false
  ]],
    5000
  )
end

T["dir_preview"]["PR-D-E2 open dir mirror after expand"] = function()
  e2e.exec(
    dir_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      preview = { enabled = true, debounce = 0 },
    })
  ]]
  )

  e2e.open_eda(dir_child, dir_tmp)

  -- Move cursor to "sub" line and expand via select action
  e2e.wait_until(
    dir_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("sub", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  e2e.exec(
    dir_child,
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
    action.dispatch("select", ctx)
  ]]
  )

  -- Wait for sub's scan to complete and its child x.txt to be rendered.
  -- Two-stage observation: scan completion (children_state == "loaded") and render
  -- completion (snapshot entry for the child path) — both are required because
  -- refresh_preserving runs through vim.schedule, leaving a window where the scan
  -- is done but the buffer has not yet been repainted.
  e2e.wait_for_node_loaded(dir_child, dir_tmp .. "/sub")
  e2e.wait_for_path_in_snapshot(dir_child, dir_tmp .. "/sub/x.txt")

  -- Re-position cursor onto "sub" (still open) so preview targets the sub node
  e2e.wait_until(
    dir_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("sub", 1, true) and not l:find("x.txt", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- Preview window should show the expanded subtree (x.txt visible)
  e2e.wait_until(
    dir_child,
    [[
    local main_buf = vim.api.nvim_get_current_buf()
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      if buf ~= main_buf then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for _, l in ipairs(lines) do
          if l:find("x.txt", 1, true) then return true end
        end
      end
    end
    return false
  ]],
    5000
  )
end

-- max_file_size tests
local mfs_child, mfs_tmp

T["max_file_size"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      mfs_child = e2e.spawn()
      mfs_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      -- Name files so small file comes first alphabetically (cursor starts on line 1)
      e2e.create_file(mfs_tmp .. "/aaa_small.txt", "12345")
      e2e.create_file(mfs_tmp .. "/zzz_large.txt", string.rep("x", 100))
    end,
    post_case = function()
      e2e.stop(mfs_child)
      e2e.remove_temp_dir(mfs_tmp)
    end,
  },
})

T["max_file_size"]["large file is not previewed when exceeding max_file_size"] = function()
  e2e.exec(
    mfs_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      preview = { enabled = true, debounce = 0, max_file_size = 10 },
    })
  ]]
  )

  e2e.open_eda(mfs_child, mfs_tmp)

  -- Cursor starts on aaa_small.txt (alphabetically first, within max_file_size)
  -- Preview window should appear (3 windows: empty + eda + preview)
  e2e.wait_until(mfs_child, "#vim.api.nvim_list_wins() >= 3", 5000)

  -- Verify preview shows small file content
  e2e.wait_until(
    mfs_child,
    [[
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local buf = vim.api.nvim_win_get_buf(w)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for _, l in ipairs(lines) do
        if l:find("12345", 1, true) then return true end
      end
    end
    return false
  ]],
    5000
  )

  -- Move cursor to zzz_large.txt — preview should close (exceeds max_file_size=10)
  e2e.wait_until(
    mfs_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("zzz_large.txt", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  -- The preview window should close since the file exceeds max_file_size
  e2e.wait_until(
    mfs_child,
    [[
    local eda_wins = 0
    local other_wins = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "eda" then
        eda_wins = eda_wins + 1
      else
        other_wins = other_wins + 1
      end
    end
    return other_wins <= 1
  ]],
    5000
  )
end

return T
