local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

local function sh(args)
  return vim.fn.system(args)
end

local function trim(s)
  return (s:gsub("%s+$", ""))
end

--- Initialize a git repo at `dir` on branch `main` with one committed file
--- (src/foo.lua) and a sub-directory src/. Returns the commit SHA.
---@param dir string
---@return string sha
local function init_repo(dir)
  sh({ "git", "init", "-b", "main", dir })
  sh({ "git", "-C", dir, "config", "user.email", "test@test.com" })
  sh({ "git", "-C", dir, "config", "user.name", "Test" })
  e2e.create_dir(dir .. "/src")
  e2e.create_file(dir .. "/src/foo.lua", "return 1\n")
  sh({ "git", "-C", dir, "add", "." })
  sh({ "git", "-C", dir, "commit", "-m", "init" })
  return trim(sh({ "git", "-C", dir, "rev-parse", "HEAD" }))
end

--- Add `origin` remote (with the given URL) and seed remote-tracking refs so
--- branch / SHA / default-branch fallbacks all have a happy local path.
---@param dir string
---@param sha string
---@param remote_url? string
local function seed_origin(dir, sha, remote_url)
  remote_url = remote_url or "git@github.com:foo/bar.git"
  sh({ "git", "-C", dir, "remote", "add", "origin", remote_url })
  sh({ "git", "-C", dir, "update-ref", "refs/remotes/origin/main", sha })
  sh({ "git", "-C", dir, "branch", "--set-upstream-to=origin/main", "main" })
  sh({ "git", "-C", dir, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main" })
end

local function setup_eda_with_git(c)
  e2e.exec(
    c,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      open_in_browser = { ref = "branch", url_builder = nil },
    })
  ]]
  )
end

local function inject_ui_open_stub(c)
  e2e.exec(
    c,
    [[
    _G.__eda_open_url = nil
    _G.__eda_notify = {}
    vim.ui.open = function(url) _G.__eda_open_url = url end
    local orig = vim.notify
    vim.notify = function(msg, level)
      table.insert(_G.__eda_notify, { msg = msg, level = level })
    end
    _G.__eda_notify_orig = orig
  ]]
  )
end

local function wait_for_git_ready()
  e2e.wait_until(
    child,
    string.format(
      [[
      local g = require("eda.git")
      return g.get_status_ready(%q) == "ready"
    ]],
      tmp
    )
  )
end

local function wait_for_file_in_buffer(name)
  e2e.wait_until(
    child,
    string.format(
      [[
      for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if l:find(%q, 1, true) then return true end
      end
      return false
    ]],
      name
    )
  )
end

local function cursor_to(name)
  e2e.exec(
    child,
    string.format(
      [[
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
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

local function captured_url()
  return e2e.exec(child, "return _G.__eda_open_url")
end

local function captured_notifications()
  return e2e.exec(child, "return _G.__eda_notify or {}")
end

T["open_in_browser"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["open_in_browser"]["keymap path opens branch URL for a committed file"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/blob/main/src/foo.lua")
end

T["open_in_browser"]["dispatch path opens branch URL"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.exec(
    child,
    [[
    local eda = require("eda")
    local exp = eda.get_current()
    local action = require("eda.action")
    action.dispatch("open_in_browser", {
      store = exp.store,
      buffer = exp.buffer,
      window = exp.window,
      scanner = exp.scanner,
      config = require("eda.config").get(),
      explorer = exp,
    })
  ]]
  )
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/blob/main/src/foo.lua")
end

T["open_in_browser"]["directory node uses /tree/ in URL"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("src")
  wait_for_git_ready()
  cursor_to("src")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/tree/main/src")
end

T["open_in_browser"]["untracked file is blocked with notification"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  e2e.create_file(tmp .. "/untracked.lua", "x")
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("untracked.lua")
  wait_for_git_ready()
  cursor_to("untracked.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(
    child,
    [[
      for _, n in ipairs(_G.__eda_notify or {}) do
        if n.msg:find("untracked", 1, true) then return true end
      end
      return false
    ]]
  )
  MiniTest.expect.equality(captured_url(), vim.NIL)
end

T["open_in_browser"]["detached HEAD falls back to SHA URL"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  sh({ "git", "-C", tmp, "checkout", "--quiet", sha })
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  local url = captured_url()
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/" .. sha .. "/src/foo.lua")
end

T["open_in_browser"]["no upstream falls back to SHA URL"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  -- Drop upstream tracking but keep refs/remotes/origin/main so SHA is on remote.
  sh({ "git", "-C", tmp, "branch", "--unset-upstream" })
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/blob/" .. sha .. "/src/foo.lua")
end

T["open_in_browser"]["default branch fallback when origin/HEAD missing"] = function()
  local sha = init_repo(tmp)
  -- Set up remote + origin/main ref + upstream but DELETE origin/HEAD so we
  -- exercise the origin/main probe fallback. Use config sha = "deadbeef" so
  -- 'branch -r --contains' finds nothing → falls through to default_branch.
  sh({ "git", "-C", tmp, "remote", "add", "origin", "git@github.com:foo/bar.git" })
  sh({ "git", "-C", tmp, "update-ref", "refs/remotes/origin/main", sha })
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      open_in_browser = { ref = "default_branch", url_builder = nil },
    })
  ]]
  )
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/blob/main/src/foo.lua")
end

T["open_in_browser"]["URL path is relative to git_root, not eda root"] = function()
  -- eda is opened at tmp/src (a subdirectory of the git repo at tmp) so the
  -- URL must include 'src/' even though the eda explorer root has hidden it.
  local sha = init_repo(tmp)
  seed_origin(tmp, sha)
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  local sub_dir = vim.uv.fs_realpath(tmp .. "/src")
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], sub_dir))
  e2e.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  e2e.wait_until(
    child,
    string.format(
      [[
      local g = require("eda.git")
      return g.get_status_ready(%q) == "ready"
    ]],
      sub_dir
    )
  )
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.com/foo/bar/blob/main/src/foo.lua")
end

T["open_in_browser"]["GHE host is preserved in URL"] = function()
  local sha = init_repo(tmp)
  seed_origin(tmp, sha, "git@github.example.com:foo/bar.git")
  setup_eda_with_git(child)
  inject_ui_open_stub(child)
  e2e.open_eda(child, tmp)
  e2e.feed(child, "gE")
  wait_for_file_in_buffer("foo.lua")
  wait_for_git_ready()
  cursor_to("foo.lua")
  e2e.feed(child, "gO")
  e2e.wait_until(child, "_G.__eda_open_url ~= nil")
  MiniTest.expect.equality(captured_url(), "https://github.example.com/foo/bar/blob/main/src/foo.lua")
end

return T
