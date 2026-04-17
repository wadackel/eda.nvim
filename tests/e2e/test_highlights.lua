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
    vim.api.nvim_set_hl(0, "EdaMarkedNode", { fg = 0xa8a384, bold = true, underline = true })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarkedNode", link = false })
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
    vim.api.nvim_set_hl(0, "EdaMarkedNode", {
      fg = 0xa8a384,
      bg = 0x222222,
      ctermbg = 8,
      bold = true,
    })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarkedNode", link = false })
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

T["highlights"]["falls back to Special when EdaMarkedNode is undefined"] = function()
  local result = e2e.exec(
    child,
    [[
    vim.api.nvim_set_hl(0, "Special", { fg = 0xff00ff })
    vim.api.nvim_set_hl(0, "EdaMarkedNode", {})
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarkedNode", link = false })
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
    vim.api.nvim_set_hl(0, "EdaMarkedNode", { link = "DiffAdd" })
    require("eda").setup({})
    local h = vim.api.nvim_get_hl(0, { name = "EdaMarkedNode", link = false })
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
    -- :hi clear wipes the override (so EdaMarkedNode falls back to link=Special),
    -- then Special is redefined with bg, then ColorScheme fires the autocmd to
    -- re-strip bg on EdaMarkedNode.
    vim.cmd("hi clear")
    vim.api.nvim_set_hl(0, "Special", { fg = 0x123456, bg = 0x654321 })
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    local marked = vim.api.nvim_get_hl(0, { name = "EdaMarkedNode", link = false })
    return {
      marked_fg = marked.fg,
      marked_has_bg = marked.bg ~= nil,
    }
  ]]
  )

  MiniTest.expect.equality(result.marked_fg, 0x123456)
  MiniTest.expect.equality(result.marked_has_bg, false)
end

return T
