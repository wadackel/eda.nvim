local action = require("eda.action")
local Store = require("eda.tree.store")

require("eda.action.builtin")

local T = MiniTest.new_set()

local TEST_URL = "https://github.com/foo/bar/blob/main/file.lua"

--- Captured state per test. `before_each` / `after_each` reset this and the
--- vim.ui.open / module stubs around each case.
---@class TestState
---@field opened string[]
---@field notified {msg: string, level: integer}[]

---@type TestState
local state = { opened = {}, notified = {} }

local original = {
  ui_open = nil,
  notify = nil,
  git = nil,
  git_url = nil,
}

local function reset_state()
  state.opened = {}
  state.notified = {}
end

local function install_stubs(stub_config)
  stub_config = stub_config or {}
  reset_state()

  -- Stub vim.ui.open
  original.ui_open = vim.ui.open
  vim.ui.open = function(url)
    table.insert(state.opened, url)
  end

  -- Stub vim.notify
  original.notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(state.notified, { msg = msg, level = level })
  end

  -- Stub eda.git (function-level overrides on the module table)
  local git = require("eda.git")
  original.git = {
    find_git_root = git.find_git_root,
    get_status_ready = git.get_status_ready,
    get_cached = git.get_cached,
  }
  git.find_git_root = function(_)
    return stub_config.git_root or "/repo"
  end
  git.get_status_ready = function(_)
    return stub_config.status_ready or "ready"
  end
  git.get_cached = function(_)
    return stub_config.statuses or {}
  end

  -- Stub eda.git_url
  local git_url = require("eda.git_url")
  original.git_url = {
    resolve_remote_url = git_url.resolve_remote_url,
    parse_remote = git_url.parse_remote,
    resolve_ref = git_url.resolve_ref,
    build_url = git_url.build_url,
  }
  git_url.resolve_remote_url = function(_)
    return stub_config.remote_url or "git@github.com:foo/bar.git"
  end
  git_url.parse_remote = function(_)
    if stub_config.parse_remote_nil then
      return nil
    end
    return { host = "github.com", owner = "foo", repo = "bar" }
  end
  git_url.resolve_ref = function(_, _)
    if stub_config.resolve_ref_nil then
      return nil
    end
    return { ref = "main", ref_kind = "branch" }
  end
  git_url.build_url = function(_, _)
    return TEST_URL
  end
end

local function restore_stubs()
  vim.ui.open = original.ui_open
  vim.notify = original.notify
  if original.git then
    local git = require("eda.git")
    for k, v in pairs(original.git) do
      git[k] = v
    end
  end
  if original.git_url then
    local git_url = require("eda.git_url")
    for k, v in pairs(original.git_url) do
      git_url[k] = v
    end
  end
end

--- Build a minimal context with one or more nodes targeted via cursor / marks / visual.
---@param opts { cursor_id?: integer, marked_ids?: integer[], visual_ids?: integer[], config?: table }
---@return table
local function make_ctx(opts)
  opts = opts or {}
  local store = Store.new()
  local root = store:set_root("/repo")
  store:add({ name = "file1.lua", path = "/repo/file1.lua", type = "file", parent_id = root })
  store:add({ name = "file2.lua", path = "/repo/file2.lua", type = "file", parent_id = root })
  store:add({ name = "dir_a", path = "/repo/dir_a", type = "directory", parent_id = root, open = true })

  for _, id in ipairs(opts.marked_ids or {}) do
    store:get(id)._marked = true
  end

  local cursor_node = opts.cursor_id and store:get(opts.cursor_id) or nil

  local mock_bufnr = vim.api.nvim_create_buf(false, true)

  local visual_ids = opts.visual_ids
  local flat_lines = {}
  if visual_ids then
    for i, id in ipairs(visual_ids) do
      flat_lines[i] = { node_id = id }
    end
  end

  local ctx = {
    store = store,
    buffer = {
      bufnr = mock_bufnr,
      get_cursor_node = function()
        return cursor_node
      end,
      flat_lines = flat_lines,
      header_lines = 0,
    },
    window = { winid = 0 },
    scanner = {},
    config = opts.config or {
      git = { enabled = true },
      open_in_browser = { ref = "branch", url_builder = nil },
    },
    explorer = { root_path = "/repo" },
  }
  return ctx
end

local function find_notify(predicate)
  for _, n in ipairs(state.notified) do
    if predicate(n.msg) then
      return n
    end
  end
  return nil
end

--- A test hook that activates visual mode (line-wise) over a given line range
--- so `_get_visual_targets` in builtin.lua reads the correct range. We sidestep
--- the real visual range by patching `get_cursor_node` plus using flat_lines and
--- letting the action grab marked/cursor first instead. For multi-target Visual
--- tests we route via marks (origin == "marks" with 2 nodes) — equivalent for
--- the "single only" assertion.
local function setup_marks_two(opts)
  install_stubs(opts)
  return make_ctx({ marked_ids = { 2, 3 } })
end

-- Hook setup: restore stubs after every case to prevent leakage.
T = MiniTest.new_set({
  hooks = {
    post_case = function()
      restore_stubs()
    end,
  },
})

-----------------------------------------------------------
-- ctx empty / multi-target
-----------------------------------------------------------
T["ctx_empty_is_silent_no_op"] = function()
  install_stubs()
  local ctx = make_ctx({}) -- no cursor, no marks, no visual
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  MiniTest.expect.equality(#state.notified, 0)
end

T["multi_marks_notifies_and_does_not_open"] = function()
  local ctx = setup_marks_two({})
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("single node", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

-----------------------------------------------------------
-- git status block: ? / A / !
-----------------------------------------------------------
T["status_untracked_is_blocked"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "?" } })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("untracked", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

T["status_added_is_blocked"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "A" } })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("added", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

T["status_ignored_is_blocked"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "!" } })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("gitignored", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

-----------------------------------------------------------
-- happy paths: M / clean / R
-----------------------------------------------------------
T["status_modified_opens_url"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "M" } })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(state.opened, { TEST_URL })
end

T["status_clean_opens_url"] = function()
  install_stubs({ statuses = {} })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(state.opened, { TEST_URL })
end

T["status_renamed_opens_url"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "R" } })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(state.opened, { TEST_URL })
end

-----------------------------------------------------------
-- config bypass + git readiness
-----------------------------------------------------------
T["git_disabled_bypasses_status_check"] = function()
  install_stubs({ statuses = { ["/repo/file1.lua"] = "?" } }) -- untracked but we expect bypass
  local ctx = make_ctx({
    cursor_id = 2,
    config = {
      git = { enabled = false },
      open_in_browser = { ref = "branch", url_builder = nil },
    },
  })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(state.opened, { TEST_URL })
end

T["git_loading_notifies_and_blocks"] = function()
  install_stubs({ status_ready = "loading" })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("not ready", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

T["git_no_repo_notifies_and_blocks"] = function()
  install_stubs({ status_ready = "no_repo" })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("not in a git repository", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

-----------------------------------------------------------
-- URL composition failures
-----------------------------------------------------------
T["unparseable_remote_notifies_and_blocks"] = function()
  install_stubs({ parse_remote_nil = true })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("parse remote", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

T["unresolvable_ref_notifies_and_blocks"] = function()
  install_stubs({ resolve_ref_nil = true })
  local ctx = make_ctx({ cursor_id = 2 })
  action.dispatch("open_in_browser", ctx)
  MiniTest.expect.equality(#state.opened, 0)
  local m = find_notify(function(msg)
    return msg:find("remote-known ref", 1, true) ~= nil
  end)
  MiniTest.expect.no_equality(m, nil)
end

return T
