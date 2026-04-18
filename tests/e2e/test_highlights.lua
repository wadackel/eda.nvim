local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child

T["highlights"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
    end,
    post_case = function()
      e2e.stop(child)
    end,
  },
})

T["highlights"]["direct definition preserves user attributes"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "EdaMarked", { fg = 0xa8a384, bold = true, underline = true })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarked", link = false })
    return {
      fg = h.fg,
      bold = h.bold,
      underline = h.underline,
      has_bg = h.bg ~= nil,
      has_ctermbg = h.ctermbg ~= nil,
    }
  ]]
  )

  MiniTest.expect.equality(result.fg, 0xa8a384)
  MiniTest.expect.equality(result.bold, true)
  MiniTest.expect.equality(result.underline, true)
  MiniTest.expect.equality(result.has_bg, false)
  MiniTest.expect.equality(result.has_ctermbg, false)
end

T["highlights"]["strips bg and ctermbg while keeping attributes"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "EdaMarked", {
      fg = 0xa8a384,
      bg = 0x222222,
      ctermbg = 8,
      bold = true,
    })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarked", link = false })
    return {
      fg = h.fg,
      bold = h.bold,
      has_bg = h.bg ~= nil,
      has_ctermbg = h.ctermbg ~= nil,
      cterm_has_bg = type(h.cterm) == "table" and h.cterm.bg ~= nil or false,
    }
  ]]
  )

  MiniTest.expect.equality(result.fg, 0xa8a384)
  MiniTest.expect.equality(result.bold, true)
  MiniTest.expect.equality(result.has_bg, false)
  MiniTest.expect.equality(result.has_ctermbg, false)
  MiniTest.expect.equality(result.cterm_has_bg, false)
end

T["highlights"]["falls back to Special when EdaMarked is undefined"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "Special", { fg = 0xff00ff })
    vim.api.nvim_set_hl(0, "EdaMarked", {})
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarked", link = false })
    return { fg = h.fg, has_bg = h.bg ~= nil }
  ]]
  )

  MiniTest.expect.equality(result.fg, 0xff00ff)
  MiniTest.expect.equality(result.has_bg, false)
end

T["highlights"]["flattens link chain and strips bg"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "DiffAdd", { fg = 0x00ff00, bg = 0x003300 })
    vim.api.nvim_set_hl(0, "EdaMarked", { link = "DiffAdd" })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarked", link = false })
    return { fg = h.fg, has_bg = h.bg ~= nil }
  ]]
  )

  MiniTest.expect.equality(result.fg, 0x00ff00)
  MiniTest.expect.equality(result.has_bg, false)
end

T["highlights"]["ColorScheme autocmd strips bg after :hi clear when new Special has bg"] = function()
  local result = e2e.exec(
    child,
    [[
    require("eda").setup({})
    -- Simulate a colorscheme that defines Special with bg.
    -- :hi clear wipes the override (so EdaMarked falls back to link=Special),
    -- then Special is redefined with bg, then ColorScheme fires the autocmd to
    -- re-strip bg on EdaMarked.
    vim.cmd("hi clear")
    vim.api.nvim_set_hl(0, "Special", { fg = 0x123456, bg = 0x654321 })
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    local marked = vim.api.nvim_get_hl(0, { name = "EdaMarked", link = false })
    return {
      marked_fg = marked.fg,
      marked_has_bg = marked.bg ~= nil,
    }
  ]]
  )

  MiniTest.expect.equality(result.marked_fg, 0x123456)
  MiniTest.expect.equality(result.marked_has_bg, false)
end

T["highlights"]["icon and name inherit fg from EdaMarked base via link chain"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "Special", { fg = 0xff00ff })
    require("eda").setup({})
    local icon = vim.api.nvim_get_hl(0, { name = "EdaMarkedIcon", link = false })
    local name = vim.api.nvim_get_hl(0, { name = "EdaMarkedName", link = false })
    return {
      icon_fg = icon.fg,
      name_fg = name.fg,
      icon_has_bg = icon.bg ~= nil,
      name_has_bg = name.bg ~= nil,
    }
  ]]
  )

  MiniTest.expect.equality(result.icon_fg, 0xff00ff)
  MiniTest.expect.equality(result.name_fg, 0xff00ff)
  MiniTest.expect.equality(result.icon_has_bg, false)
  MiniTest.expect.equality(result.name_has_bg, false)
end

T["highlights"]["icon and name can be overridden independently"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "EdaMarkedIcon", { fg = 0xff0000 })
    vim.api.nvim_set_hl(0, "EdaMarkedName", { fg = 0x0000ff, underline = true })
    require("eda").setup({})
    local icon = vim.api.nvim_get_hl(0, { name = "EdaMarkedIcon", link = false })
    local name = vim.api.nvim_get_hl(0, { name = "EdaMarkedName", link = false })
    return {
      icon_fg = icon.fg,
      name_fg = name.fg,
      name_underline = name.underline,
    }
  ]]
  )

  MiniTest.expect.equality(result.icon_fg, 0xff0000)
  MiniTest.expect.equality(result.name_fg, 0x0000ff)
  MiniTest.expect.equality(result.name_underline, true)
end

T["highlights"]["ignored + marked: decoration cache stacks git and mark name hls"] = function()
  -- Regression guard for the real-world bug: when a gitignored node is marked,
  -- the Chain used to emit `{ "EdaGitIgnoredName", "EdaMarkedName" }` as a single
  -- extmark array. Neovim does not resolve link chains inside hl_group arrays,
  -- so the link-only EdaMarkedName silently lost its fg and the filename stayed
  -- the ignored color. The decoration cache must contain both hl groups in order
  -- (git first, mark last), and the on_line per-element emission (covered by the
  -- unit test in test_painter.lua) makes the later element win.
  --
  -- Note: headless --listen mode does not fire the decoration provider's on_line
  -- callback, so this E2E verifies the cache that feeds on_line, not the final
  -- extmark calls.
  local tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
  e2e.create_file(tmp .. "/.gitignore", "ignored.txt\n")
  e2e.create_file(tmp .. "/ignored.txt", "content")
  e2e.create_git_repo(tmp)

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_gitignored = true,
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  e2e.wait_until(child, string.format([[require("eda.git").get_cached(%q) ~= nil]], tmp), 10000)

  e2e.exec(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    for idx, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "ignored.txt" then
        vim.api.nvim_win_set_cursor(0, { idx, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "m")
  e2e.wait_until(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    for _, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "ignored.txt" and fl.node._marked then
        return true
      end
    end
    return false
  ]]
  )

  local result = e2e.exec(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    local ignored_id
    for _, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "ignored.txt" then
        ignored_id = fl.node_id
        break
      end
    end
    local entry = buffer.painter._decoration_cache[ignored_id]
    return {
      name_hl = entry and entry.name_hl or nil,
      type_tag = entry and type(entry.name_hl) or nil,
    }
  ]]
  )

  -- The cache entry for ignored.txt must contain an array with both hl groups,
  -- with EdaMarkedName placed last (so on_line's per-element emission assigns it
  -- the highest priority and its link chain wins the final rendered fg).
  MiniTest.expect.equality(result.type_tag, "table")
  MiniTest.expect.equality(type(result.name_hl), "table")
  MiniTest.expect.equality(result.name_hl[1], "EdaGitIgnoredName")
  MiniTest.expect.equality(result.name_hl[#result.name_hl], "EdaMarkedName")

  e2e.remove_temp_dir(tmp)
end

T["highlights"]["symlink + marked: decoration cache stacks symlink and mark name hls"] = function()
  -- Regression guard: marked symlink must place EdaMarkedName after EdaSymlink in the
  -- decoration cache array so on_line's per-element emission gives mark the highest
  -- priority and its fg wins over Underlined's fg.
  -- Note: headless --listen mode does not fire on_line, so this E2E verifies the
  -- cache feeding on_line, not the final extmark calls.
  local tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
  e2e.create_file(tmp .. "/real.txt", "content")
  vim.uv.fs_symlink(tmp .. "/real.txt", tmp .. "/link.txt")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      git = { enabled = false },
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  e2e.exec(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    for idx, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "link.txt" then
        vim.api.nvim_win_set_cursor(0, { idx, 0 })
        break
      end
    end
  ]]
  )
  e2e.feed(child, "m")
  e2e.wait_until(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    for _, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "link.txt" and fl.node._marked then
        return true
      end
    end
    return false
  ]]
  )

  local result = e2e.exec(
    child,
    [[
    local buffer = require("eda").get_current().buffer
    local link_id
    for _, fl in ipairs(buffer.flat_lines) do
      if fl.node.name == "link.txt" then
        link_id = fl.node_id
        break
      end
    end
    local entry = buffer.painter._decoration_cache[link_id]
    return {
      name_hl = entry and entry.name_hl or nil,
      type_tag = entry and type(entry.name_hl) or nil,
    }
  ]]
  )

  MiniTest.expect.equality(result.type_tag, "table")
  MiniTest.expect.equality(type(result.name_hl), "table")
  MiniTest.expect.equality(result.name_hl[1], "EdaSymlink")
  MiniTest.expect.equality(result.name_hl[#result.name_hl], "EdaMarkedName")

  e2e.remove_temp_dir(tmp)
end

return T
