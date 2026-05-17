local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

---Inject a mock clipboard provider so vim.fn.setreg("+", ...) writes to
---_G.__yank_tree_clip instead of the OS clipboard (which is provider-dependent
---in --clean --headless and would pollute the developer machine on macOS).
local function inject_mock_clipboard(c)
  e2e.exec(
    c,
    [[
    _G.__yank_tree_clip = nil
    vim.g.clipboard = {
      name = "yank_tree_test_mock",
      copy = {
        ["+"] = function(lines, _) _G.__yank_tree_clip = table.concat(lines, "\n") end,
        ["*"] = function(lines, _) _G.__yank_tree_clip = table.concat(lines, "\n") end,
      },
      paste = {
        ["+"] = function() return vim.split(_G.__yank_tree_clip or "", "\n"), "v" end,
        ["*"] = function() return vim.split(_G.__yank_tree_clip or "", "\n"), "v" end,
      },
      cache_enabled = 0,
    }
  ]]
  )
end

T["yank_tree"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      inject_mock_clipboard(child)
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/src")
      e2e.create_file(tmp .. "/src/foo.ts", "foo")
      e2e.create_file(tmp .. "/src/bar.ts", "bar")
      e2e.create_dir(tmp .. "/tests")
      e2e.create_file(tmp .. "/tests/baz.ts", "baz")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

---Reset the mock clipboard buffer so each case is independent.
local function reset_clip()
  e2e.exec(child, "_G.__yank_tree_clip = nil")
end

---Read the mock clipboard buffer (post-yank).
---@return string|nil
local function read_clip()
  return e2e.exec(child, "return _G.__yank_tree_clip")
end

---Move the eda cursor to the line containing the given basename.
---Relies on the explorer being fully expanded (gE) before calling.
local function cursor_to(name)
  e2e.exec(
    child,
    string.format(
      [[
      local buf = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:find(%q, 1, true) then
          vim.api.nvim_win_set_cursor(0, { i, 0 })
          return
        end
      end
      error("no line containing " .. %q)
    ]],
      name,
      name
    )
  )
end

T["yank_tree"]["cursor: single node short-circuits to relative path"] = function()
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local has_foo, has_baz = false, false
    for _, l in ipairs(lines) do
      if l:find("foo.ts", 1, true) then has_foo = true end
      if l:find("baz.ts", 1, true) then has_baz = true end
    end
    return has_foo and has_baz
  ]]
  )

  reset_clip()
  cursor_to("foo.ts")
  e2e.feed(child, "yt")
  e2e.exec(child, "vim.wait(50)")

  MiniTest.expect.equality(read_clip(), "src/foo.ts")
end

T["yank_tree"]["marks: cross-directory selection renders ASCII tree and clears marks"] = function()
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local has_foo, has_baz = false, false
    for _, l in ipairs(lines) do
      if l:find("foo.ts", 1, true) then has_foo = true end
      if l:find("baz.ts", 1, true) then has_baz = true end
    end
    return has_foo and has_baz
  ]]
  )

  -- Mark src/foo.ts + tests/baz.ts (cross-directory).
  cursor_to("foo.ts")
  e2e.feed(child, "m")
  cursor_to("baz.ts")
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

  reset_clip()
  e2e.feed(child, "yt")
  e2e.exec(child, "vim.wait(50)")

  local expected = table.concat({
    "./",
    "├── src/",
    "│   └── foo.ts",
    "└── tests/",
    "    └── baz.ts",
  }, "\n")
  MiniTest.expect.equality(read_clip(), expected)

  -- Marks must be cleared after a marks-origin yank.
  e2e.wait_until(
    child,
    [[
    local buf = require("eda").get_current().buffer
    for _, fl in ipairs(buf.flat_lines) do
      if fl.node._marked then return false end
    end
    return true
  ]]
  )
end

T["yank_tree"]["visual: V-line range renders ASCII tree under common ancestor"] = function()
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local has_bar, has_foo = false, false
    for _, l in ipairs(lines) do
      if l:find("bar.ts", 1, true) then has_bar = true end
      if l:find("foo.ts", 1, true) then has_foo = true end
    end
    return has_bar and has_foo
  ]]
  )

  -- Move cursor to bar.ts, then V-line down to foo.ts (siblings under src/).
  cursor_to("bar.ts")
  e2e.feed(child, "Vj")
  e2e.exec(child, "vim.wait(20)")

  reset_clip()
  e2e.feed(child, "yt")
  e2e.exec(child, "vim.wait(50)")

  local expected = table.concat({
    "src/",
    "├── bar.ts",
    "└── foo.ts",
  }, "\n")
  MiniTest.expect.equality(read_clip(), expected)
end

return T
