local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

-- indent.width tests
local indent_child, indent_tmp

T["indent"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      indent_child = e2e.spawn()
      indent_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(indent_tmp .. "/sub")
      e2e.create_file(indent_tmp .. "/sub/child.txt", "child")
    end,
    post_case = function()
      e2e.stop(indent_child)
      e2e.remove_temp_dir(indent_tmp)
    end,
  },
})

T["indent"]["indent.width=4 produces 4-space indentation"] = function()
  e2e.exec(
    indent_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      indent = { width = 4 },
    })
  ]]
  )

  e2e.open_eda(indent_child, indent_tmp)

  -- Expand sub/ directory
  e2e.exec(indent_child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(indent_child, "<CR>")
  e2e.wait_until(
    indent_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("child.txt", 1, true) then return true end
    end
    return false
  ]]
  )

  local lines = e2e.get_buf_lines(indent_child)
  for _, line in ipairs(lines) do
    if line:find("child.txt", 1, true) then
      -- Should start with exactly 4 spaces
      MiniTest.expect.equality(line:match("^    %S") ~= nil, true)
      -- Should NOT start with 2 spaces followed by non-space (default indent)
      MiniTest.expect.equality(line:sub(1, 2) == "  " and line:sub(3, 3) ~= " ", false)
      break
    end
  end
end

T["indent"]["indent.width=1 produces 1-space indentation"] = function()
  e2e.exec(
    indent_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      indent = { width = 1 },
    })
  ]]
  )

  e2e.open_eda(indent_child, indent_tmp)

  -- Expand sub/ directory
  e2e.exec(indent_child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(indent_child, "<CR>")
  e2e.wait_until(
    indent_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("child.txt", 1, true) then return true end
    end
    return false
  ]]
  )

  local lines = e2e.get_buf_lines(indent_child)
  for _, line in ipairs(lines) do
    if line:find("child.txt", 1, true) then
      -- Should start with exactly 1 space then non-space
      MiniTest.expect.equality(line:match("^ %S") ~= nil, true)
      break
    end
  end
end

-- expand_depth tests
local depth_child, depth_tmp

T["expand_depth"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      depth_child = e2e.spawn()
      depth_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(depth_tmp .. "/a/b/c/d")
      e2e.create_file(depth_tmp .. "/a/b/c/d/deep.txt", "deep")
      e2e.create_file(depth_tmp .. "/a/b/inner.txt", "inner")
    end,
    post_case = function()
      e2e.stop(depth_child)
      e2e.remove_temp_dir(depth_tmp)
    end,
  },
})

-- expand_depth semantics: scan_recursive(root, N) scans root, then recurses
-- with N-1 on each dir child. At N<=0, returns without scanning.
-- So expand_depth=2 scans: root → a/ → (b/ NOT scanned because N-2=0).
-- open_all only opens dirs with children_state=="loaded" (i.e., scanned).

T["expand_depth"]["expand_depth=2 limits expand_all depth"] = function()
  e2e.exec(
    depth_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      expand_depth = 2,
    })
  ]]
  )

  e2e.open_eda(depth_child, depth_tmp)

  -- Expand all with gE
  e2e.feed(depth_child, "gE")

  -- With expand_depth=2: root scanned, a/ scanned, b/ NOT scanned.
  -- open_all opens root and a/, so b/ is visible (as collapsed dir).
  -- inner.txt is NOT visible (b/ was not scanned so its children are not loaded).
  e2e.wait_until(
    depth_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("b/", 1, true) then return true end
    end
    return false
  ]],
    5000
  )

  local lines = e2e.get_buf_lines(depth_child)
  local has_inner = false
  local has_deep = false
  for _, line in ipairs(lines) do
    if line:find("inner.txt", 1, true) then
      has_inner = true
    end
    if line:find("deep.txt", 1, true) then
      has_deep = true
    end
  end
  -- b/ is visible but not opened, so its children are not shown
  MiniTest.expect.equality(has_inner, false)
  MiniTest.expect.equality(has_deep, false)
end

T["expand_depth"]["expand_depth=1 expands only one level"] = function()
  e2e.exec(
    depth_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      expand_depth = 1,
    })
  ]]
  )

  e2e.open_eda(depth_child, depth_tmp)

  -- Expand all with gE
  e2e.feed(depth_child, "gE")

  -- With expand_depth=1: root scanned, a/ NOT scanned (scan_recursive(a,0) returns).
  -- open_all opens root only. a/ is visible as collapsed dir.
  e2e.wait_until(
    depth_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("a/", 1, true) then return true end
    end
    return false
  ]],
    5000
  )

  -- b/ should NOT appear (a/ was not scanned, so its children are not loaded)
  local lines = e2e.get_buf_lines(depth_child)
  local has_b = false
  for _, line in ipairs(lines) do
    if line:find("b/", 1, true) then
      has_b = true
    end
  end
  MiniTest.expect.equality(has_b, false)
end

-- follow_symlinks tests
local sym_child, sym_tmp

T["follow_symlinks"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      sym_child = e2e.spawn()
      sym_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(sym_tmp .. "/real")
      e2e.create_file(sym_tmp .. "/real/inner.txt", "inner")
      vim.uv.fs_symlink(sym_tmp .. "/real", sym_tmp .. "/link", { dir = true })
    end,
    post_case = function()
      e2e.stop(sym_child)
      e2e.remove_temp_dir(sym_tmp)
    end,
  },
})

T["follow_symlinks"]["follow_symlinks=true traverses symlink directories"] = function()
  e2e.exec(
    sym_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      follow_symlinks = true,
    })
  ]]
  )

  e2e.open_eda(sym_child, sym_tmp)

  -- link should appear as a directory (with trailing /)
  e2e.wait_until(
    sym_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("link/", 1, true) then return true end
    end
    return false
  ]]
  )

  -- Find and expand link/
  e2e.wait_until(
    sym_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("link/", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  e2e.feed(sym_child, "<CR>")

  -- inner.txt should appear after expansion
  e2e.wait_until(
    sym_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("inner.txt", 1, true) then return true end
    end
    return false
  ]]
  )
end

T["follow_symlinks"]["follow_symlinks=false shows symlink as non-directory"] = function()
  e2e.exec(
    sym_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      follow_symlinks = false,
    })
  ]]
  )

  e2e.open_eda(sym_child, sym_tmp)

  -- Wait for buffer to render
  e2e.wait_until(
    sym_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("link", 1, true) then return true end
    end
    return false
  ]]
  )

  local lines = e2e.get_buf_lines(sym_child)

  -- link should NOT have trailing / (not treated as directory)
  local has_link_dir = false
  local has_link = false
  for _, line in ipairs(lines) do
    if line:find("link/", 1, true) then
      has_link_dir = true
    end
    if line:find("link", 1, true) then
      has_link = true
    end
  end
  MiniTest.expect.equality(has_link, true)
  MiniTest.expect.equality(has_link_dir, false)

  -- Pressing CR on link should not expand (line count stays the same)
  local line_count_before = #lines

  -- Move to link line
  e2e.wait_until(
    sym_child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("link", 1, true) then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )

  e2e.feed(sym_child, "<CR>")
  vim.uv.sleep(200) -- e2e-sleep-allowed: negative-assertion guard (symlink <CR> must not expand in eda buffer)

  -- Line count should remain the same (no expansion occurred in eda buffer)
  local eda_line_count = e2e.exec(
    sym_child,
    [[
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "eda" then
        return vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(w))
      end
    end
    return 0
  ]]
  )
  MiniTest.expect.equality(eda_line_count, line_count_before)
end

-- default_mappings tests
local map_child, map_tmp

T["default_mappings"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      map_child = e2e.spawn()
      map_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(map_tmp .. "/file.txt", "content")
    end,
    post_case = function()
      e2e.stop(map_child)
      e2e.remove_temp_dir(map_tmp)
    end,
  },
})

T["default_mappings"]["default_mappings=false removes all keymaps"] = function()
  e2e.exec(
    map_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      default_mappings = false,
    })
  ]]
  )

  e2e.open_eda(map_child, map_tmp)

  local keymaps = e2e.exec(map_child, "return vim.api.nvim_buf_get_keymap(0, 'n')")
  MiniTest.expect.equality(#keymaps, 0)
end

-- on_highlight tests
local hl_child, hl_tmp

T["on_highlight"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      hl_child = e2e.spawn()
      hl_tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(hl_tmp .. "/file.txt", "content")
    end,
    post_case = function()
      e2e.stop(hl_child)
      e2e.remove_temp_dir(hl_tmp)
    end,
  },
})

T["on_highlight"]["on_highlight callback modifies highlight groups"] = function()
  e2e.exec(
    hl_child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      on_highlight = function(groups)
        groups.EdaFileName = { fg = "#ff0000" }
      end,
    })
  ]]
  )

  e2e.open_eda(hl_child, hl_tmp)

  local fg = e2e.exec(hl_child, "return vim.api.nvim_get_hl(0, { name = 'EdaFileName', link = false }).fg")
  MiniTest.expect.equality(fg, 16711680) -- 0xff0000
end

return T
