local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["window modes"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["window modes"]["float mode starts and shows filetype eda"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  local lines = e2e.get_buf_lines(child)
  MiniTest.expect.equality(#lines > 0, true)
end

T["window modes"]["float mode closes with q"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')
end

T["window modes"]["float mode reopens in replace mode with bang"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda" and #vim.api.nvim_list_wins() == 2')

  e2e.feed(child, "!")
  e2e.wait_until(
    child,
    [[
    local has_file = false
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line:find("file.txt", 1, true) then
        has_file = true
        break
      end
    end
    return vim.bo.filetype == "eda"
      and #vim.api.nvim_list_wins() == 1
      and require("eda").get_current().window.kind == "replace"
      and require("eda").get_current().is_split == false
      and #require("eda").get_all() == 1
      and has_file
  ]]
  )
end

T["window modes"]["open_replace refuses modified float buffer"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda" and #vim.api.nvim_list_wins() == 2')

  local result = e2e.exec(
    child,
    [[
    local eda = require("eda")
    local explorer = eda.get_current()
    vim.bo[explorer.buffer.bufnr].modified = true
    require("eda.action").dispatch("open_replace", {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = require("eda.config").get(),
      explorer = explorer,
    })
    return {
      kind = eda.get_current().window.kind,
      instances = #eda.get_all(),
      windows = #vim.api.nvim_list_wins(),
      modified = vim.bo[explorer.buffer.bufnr].modified,
    }
  ]]
  )

  MiniTest.expect.equality(result.kind, "float")
  MiniTest.expect.equality(result.instances, 1)
  MiniTest.expect.equality(result.windows, 2)
  MiniTest.expect.equality(result.modified, true)
end

T["window modes"]["replace mode starts and shows filetype eda"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- Replace mode has only 1 window
  MiniTest.expect.equality(e2e.get_win_count(child), 1)
end

T["window modes"]["replace mode closes with q"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "replace" },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')
end

local REPLACE_SETUP = [[
  require("eda").setup({
    git = { enabled = false },
    icon = { provider = "none" },
    window = { kind = "replace" },
    confirm = false,
    header = false,
  })
]]

-- A single window hides the bug: wiping the explorer buffer cannot close the last
-- window, so Neovim swaps in the alternate buffer and the result looks like a restore.
-- Only a second window, or a second tabpage, tells the two apart.
T["window modes"]["replace mode hands its window back when another window is open"] = function()
  e2e.exec(child, REPLACE_SETUP)
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp .. "/file.txt"))
  e2e.exec(child, [[vim.cmd("vsplit")]])
  local wins_before = e2e.get_win_count(child)
  local previous = e2e.exec(child, [[return vim.api.nvim_buf_get_name(0)]])

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')

  MiniTest.expect.equality(e2e.get_win_count(child), wins_before)
  MiniTest.expect.equality(e2e.exec(child, [[return vim.api.nvim_buf_get_name(0)]]), previous)
end

-- The case Neovim's alternate-buffer fallback cannot fake: an unlisted buffer is not a
-- candidate for it, so only a real restore puts the help window back.
T["window modes"]["replace mode restores an unlisted previous buffer"] = function()
  e2e.exec(child, REPLACE_SETUP)
  e2e.exec(child, [[vim.cmd("vsplit"); vim.cmd("help")]])
  e2e.wait_until(child, 'vim.bo.buftype == "help"')
  local previous = e2e.exec(child, [[return vim.api.nvim_buf_get_name(0)]])
  MiniTest.expect.equality(e2e.exec(child, [[return vim.bo.buflisted]]), false)

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')

  MiniTest.expect.equality(e2e.exec(child, [[return vim.api.nvim_buf_get_name(0)]]), previous)
end

-- eda created this pane, so closing the explorer takes the pane with it rather than
-- leaving a duplicate of the neighbour behind. A plain file is opened alongside first so
-- the pane inherits a non-eda buffer: otherwise `old_bufnr` would be an eda buffer and
-- the restorability clause, not window ownership, would be what declines.
T["window modes"]["a pane opened by the split action closes with the explorer"] = function()
  -- split_left, not replace: open_split then targets the user's file window, so the new
  -- pane inherits a plain buffer. From a replace explorer it would inherit the eda
  -- buffer, and the validity of `old_bufnr` rather than ownership would be what decides.
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp .. "/file.txt"))
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')
  local wins_before = e2e.get_win_count(child)

  e2e.exec(child, string.format([[require("eda").open_split(%q)]], tmp))
  e2e.wait_until(child, "#require('eda').get_all() == 2", 10000)
  MiniTest.expect.equality(e2e.get_win_count(child), wins_before + 1)
  MiniTest.expect.equality(
    e2e.exec(child, [[return vim.bo[require("eda").get_all()[2].window.old_bufnr].filetype ~= "eda"]]),
    true
  )

  e2e.exec(child, [[require("eda").close(require("eda").get_all()[2])]])
  e2e.wait_until(child, "#require('eda').get_all() == 1", 10000)
  MiniTest.expect.equality(e2e.get_win_count(child), wins_before)
end

T["window modes"]["replace mode in its own tabpage keeps the tab"] = function()
  e2e.exec(child, REPLACE_SETUP)
  e2e.exec(child, [[vim.cmd("tabnew")]])
  local tabs_before = e2e.get_tab_count(child)

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')

  MiniTest.expect.equality(e2e.get_tab_count(child), tabs_before)
end

local function open_replace_after_two_files()
  e2e.create_file(tmp .. "/code.py", "print(1)")
  e2e.exec(child, REPLACE_SETUP)
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp .. "/code.py"))
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp .. "/file.txt"))
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')
end

local function alternate_name()
  return e2e.exec(child, [[return vim.fn.bufname("#")]])
end

T["window modes"]["replace mode keeps the alternate file when closed"] = function()
  open_replace_after_two_files()

  e2e.feed(child, "q")
  e2e.wait_until(child, 'vim.bo.filetype ~= "eda"')

  MiniTest.expect.equality(vim.endswith(e2e.exec(child, [[return vim.api.nvim_buf_get_name(0)]]), "/file.txt"), true)
  MiniTest.expect.equality(vim.endswith(alternate_name(), "code.py"), true)
end

T["window modes"]["replace mode select leaves the previous file as the alternate"] = function()
  open_replace_after_two_files()
  e2e.wait_until(
    child,
    [[
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find("code.py", 1, true) then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end
    end
    return false
  ]]
  )

  e2e.feed(child, "<CR>")
  e2e.wait_until(child, [[vim.endswith(vim.api.nvim_buf_get_name(0), "/code.py") and #require("eda").get_all() == 0]])

  MiniTest.expect.equality(vim.endswith(alternate_name(), "file.txt"), true)
end

T["window modes"]["split_right mode starts and shows filetype eda"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_right", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )

  -- split_right creates 2 windows
  MiniTest.expect.equality(e2e.get_win_count(child), 2)
end

T["window modes"]["split_right mode closes with q"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_right", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, 'vim.bo.filetype == "eda"')

  e2e.feed(child, "q")
  e2e.wait_until(child, "#vim.api.nvim_list_wins() == 1")
end

return T
