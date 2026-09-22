local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["autocmd"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/sub")
      e2e.create_file(tmp .. "/file_a.txt", "a")
      e2e.create_file(tmp .. "/sub/file_b.txt", "b")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["autocmd"]["netrw hijack opens eda when editing a directory"] = function()
  -- Load netrw plugin (not loaded by default with --clean)
  -- packadd adds to rtp, then load autoload + plugin scripts explicitly
  e2e.exec(child, "vim.cmd('packadd netrw')")
  e2e.exec(child, "vim.cmd('runtime! autoload/netrw.vim')")
  e2e.exec(child, "vim.cmd('runtime plugin/netrwPlugin.vim')")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
      hijack_netrw = true,
    })
  ]]
  )

  -- Edit a directory — should trigger hijack
  e2e.exec(child, string.format("vim.cmd('edit %s')", tmp))

  -- Wait for eda to open
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]],
    10000
  )

  -- Should display the directory contents
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("file_a.txt") then return true end
    end
    return false
  ]],
    5000
  )
end

T["autocmd"]["netrw hijack works when setup runs after the netrw plugin loaded"] = function()
  -- Only the plugin script: sourcing autoload/netrw.vim up front would define
  -- netrw#LocalBrowseCheck and hide the E117 raised by netrw's leftover BufEnter.
  e2e.exec(child, "vim.cmd('packadd netrw')")
  e2e.exec(child, "vim.cmd('runtime plugin/netrwPlugin.vim')")
  MiniTest.expect.equality(e2e.exec(child, "return vim.fn.exists('#FileExplorer')"), 1)

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
      hijack_netrw = true,
    })
  ]]
  )

  e2e.exec(child, "vim.v.errmsg = ''")
  local edit_err = e2e.exec(
    child,
    string.format("local ok, err = pcall(vim.cmd, 'edit %s'); return ok and vim.v.errmsg or tostring(err)", tmp)
  )
  MiniTest.expect.equality(edit_err:match("E117[^\n]*"), nil)

  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if vim.bo.filetype ~= "eda" then return false end
    for _, l in ipairs(lines) do
      if l:find("file_a.txt") then return true end
    end
    return false
  ]],
    10000
  )
  MiniTest.expect.equality(e2e.exec(child, "return #vim.api.nvim_get_autocmds({ group = 'FileExplorer' })"), 0)
end

-- update_focused_file / navigate() core logic is covered by unit tests
-- in tests/test_navigate.lua. E2E testing requires BufEnter autocmd which
-- does not fire in headless --listen mode.

return T
