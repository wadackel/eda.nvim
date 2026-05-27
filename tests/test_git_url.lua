local T = MiniTest.new_set()

-- Lazily reload module each test to ensure stub state is fresh.
local function load()
  package.loaded["eda.git_url"] = nil
  return require("eda.git_url")
end

--- Build a stub _exec that dispatches based on git args.
--- routes: table<string, {stdout=string, code=integer}> keyed by args joined with " ".
--- Unmatched args return {stdout="", code=1} (simulate git failure).
--- The stub ignores git_root since tests don't need to assert on it.
---@param routes table<string, table>
---@return fun(git_root: string, args: string[]): table
local function make_exec(routes)
  return function(_git_root, args)
    local key = table.concat(args, " ")
    local result = routes[key]
    if result then
      return result
    end
    return { stdout = "", code = 1 }
  end
end

-----------------------------------------------------------
-- parse_remote: scheme coverage
-----------------------------------------------------------
T["parse_remote"] = MiniTest.new_set()

local parse_cases = {
  {
    name = "ssh_shorthand_with_git_suffix",
    url = "git@github.com:foo/bar.git",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "ssh_shorthand_without_git_suffix",
    url = "git@github.com:foo/bar",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "https_with_git_suffix",
    url = "https://github.com/foo/bar.git",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "https_ghe_without_git_suffix",
    url = "https://github.example.com/foo/bar",
    expected = { host = "github.example.com", owner = "foo", repo = "bar" },
  },
  {
    name = "ssh_scheme_with_port",
    url = "ssh://git@github.com:22/foo/bar.git",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "ssh_scheme_no_port",
    url = "ssh://git@github.com/foo/bar.git",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "git_scheme",
    url = "git://github.com/foo/bar",
    expected = { host = "github.com", owner = "foo", repo = "bar" },
  },
  {
    name = "http_scheme",
    url = "http://github.example.com/foo/bar.git",
    expected = { host = "github.example.com", owner = "foo", repo = "bar" },
  },
}

for _, case in ipairs(parse_cases) do
  T["parse_remote"][case.name] = function()
    local m = load()
    MiniTest.expect.equality(m.parse_remote(case.url), case.expected)
  end
end

T["parse_remote"]["unparseable_returns_nil"] = function()
  local m = load()
  MiniTest.expect.equality(m.parse_remote("gh:foo/bar"), nil)
  MiniTest.expect.equality(m.parse_remote("not_a_url"), nil)
  MiniTest.expect.equality(m.parse_remote(""), nil)
end

-----------------------------------------------------------
-- build_github_url: URL composition + encoding
-----------------------------------------------------------
T["build_github_url"] = MiniTest.new_set()

T["build_github_url"]["file_blob"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "lua/eda/init.lua",
    node_type = "file",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/lua/eda/init.lua")
end

T["build_github_url"]["dir_tree"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "lua",
    node_type = "directory",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/tree/main/lua")
end

T["build_github_url"]["root_tree"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "",
    node_type = "directory",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/tree/main/")
end

T["build_github_url"]["path_with_space_is_encoded"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "docs/hello world.md",
    node_type = "file",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/docs/hello%20world.md")
end

T["build_github_url"]["path_with_hash_is_encoded"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "docs/issue#1.md",
    node_type = "file",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/docs/issue%231.md")
end

T["build_github_url"]["path_with_japanese_is_encoded"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "main",
    rel_path = "docs/日本語.md",
    node_type = "file",
  })
  -- "日本語" = E6 97 A5 E6 9C AC E8 AA 9E in UTF-8
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/docs/%E6%97%A5%E6%9C%AC%E8%AA%9E.md")
end

T["build_github_url"]["branch_with_slash_preserved"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "feature/foo",
    rel_path = "x.lua",
    node_type = "file",
  })
  -- Slashes inside a branch name are part of the ref hierarchy and must remain literal.
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/feature/foo/x.lua")
end

T["build_github_url"]["branch_with_hash_is_encoded"] = function()
  local m = load()
  local url = m.build_github_url({
    host = "github.com",
    owner = "foo",
    repo = "bar",
    ref = "fix#1",
    rel_path = "x.lua",
    node_type = "file",
  })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/fix%231/x.lua")
end

-----------------------------------------------------------
-- resolve_ref: fallback chain with stubbed _exec
-----------------------------------------------------------
T["resolve_ref"] = MiniTest.new_set()

T["resolve_ref"]["branch_with_upstream"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse --abbrev-ref HEAD"] = { stdout = "feature/foo\n", code = 0 },
    ["rev-parse --abbrev-ref feature/foo@{upstream}"] = { stdout = "origin/feature/foo\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "branch")
  MiniTest.expect.equality(result, { ref = "feature/foo", ref_kind = "branch" })
end

T["resolve_ref"]["branch_without_upstream_falls_back_to_pushed_sha"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse --abbrev-ref HEAD"] = { stdout = "feature/foo\n", code = 0 },
    ["rev-parse --abbrev-ref feature/foo@{upstream}"] = { stdout = "", code = 128 },
    ["rev-parse HEAD"] = { stdout = "abc123\n", code = 0 },
    ["branch -r --contains abc123"] = { stdout = "  origin/main\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "branch")
  MiniTest.expect.equality(result, { ref = "abc123", ref_kind = "sha" })
end

T["resolve_ref"]["sha_pushed"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse HEAD"] = { stdout = "abc123\n", code = 0 },
    ["branch -r --contains abc123"] = { stdout = "  origin/main\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "sha")
  MiniTest.expect.equality(result, { ref = "abc123", ref_kind = "sha" })
end

T["resolve_ref"]["sha_unpushed_falls_back_to_default_branch"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse HEAD"] = { stdout = "abc123\n", code = 0 },
    ["branch -r --contains abc123"] = { stdout = "", code = 0 },
    ["symbolic-ref --short refs/remotes/origin/HEAD"] = { stdout = "origin/main\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "sha")
  MiniTest.expect.equality(result, { ref = "main", ref_kind = "default_branch" })
end

T["resolve_ref"]["default_branch_via_origin_HEAD"] = function()
  local m = load()
  m._exec = make_exec({
    ["symbolic-ref --short refs/remotes/origin/HEAD"] = { stdout = "origin/main\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "default_branch")
  MiniTest.expect.equality(result, { ref = "main", ref_kind = "default_branch" })
end

T["resolve_ref"]["default_branch_probes_origin_main_when_HEAD_missing"] = function()
  local m = load()
  m._exec = make_exec({
    ["symbolic-ref --short refs/remotes/origin/HEAD"] = { stdout = "", code = 128 },
    ["rev-parse --verify origin/main"] = { stdout = "abc123\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "default_branch")
  MiniTest.expect.equality(result, { ref = "main", ref_kind = "default_branch" })
end

T["resolve_ref"]["default_branch_probes_origin_master_when_main_missing"] = function()
  local m = load()
  m._exec = make_exec({
    ["symbolic-ref --short refs/remotes/origin/HEAD"] = { stdout = "", code = 128 },
    ["rev-parse --verify origin/main"] = { stdout = "", code = 128 },
    ["rev-parse --verify origin/master"] = { stdout = "abc123\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "default_branch")
  MiniTest.expect.equality(result, { ref = "master", ref_kind = "default_branch" })
end

T["resolve_ref"]["all_fail_returns_nil"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse --abbrev-ref HEAD"] = { stdout = "HEAD\n", code = 0 }, -- detached
    ["rev-parse HEAD"] = { stdout = "abc123\n", code = 0 },
    ["branch -r --contains abc123"] = { stdout = "", code = 0 },
    ["symbolic-ref --short refs/remotes/origin/HEAD"] = { stdout = "", code = 128 },
    ["rev-parse --verify origin/main"] = { stdout = "", code = 128 },
    ["rev-parse --verify origin/master"] = { stdout = "", code = 128 },
  })
  local result = m.resolve_ref("/repo", "branch")
  MiniTest.expect.equality(result, nil)
end

T["resolve_ref"]["detached_HEAD_falls_to_sha_path"] = function()
  local m = load()
  m._exec = make_exec({
    ["rev-parse --abbrev-ref HEAD"] = { stdout = "HEAD\n", code = 0 },
    ["rev-parse HEAD"] = { stdout = "abc123\n", code = 0 },
    ["branch -r --contains abc123"] = { stdout = "  origin/main\n", code = 0 },
  })
  local result = m.resolve_ref("/repo", "branch")
  MiniTest.expect.equality(result, { ref = "abc123", ref_kind = "sha" })
end

-----------------------------------------------------------
-- resolve_remote_url
-----------------------------------------------------------
T["resolve_remote_url"] = MiniTest.new_set()

T["resolve_remote_url"]["returns_origin_url"] = function()
  local m = load()
  m._exec = make_exec({
    ["remote get-url origin"] = { stdout = "git@github.com:foo/bar.git\n", code = 0 },
  })
  MiniTest.expect.equality(m.resolve_remote_url("/repo"), "git@github.com:foo/bar.git")
end

T["resolve_remote_url"]["returns_nil_when_no_origin"] = function()
  local m = load()
  m._exec = make_exec({})
  MiniTest.expect.equality(m.resolve_remote_url("/repo"), nil)
end

-----------------------------------------------------------
-- build_url: url_builder override + pcall safety + ctx schema
-----------------------------------------------------------
T["build_url"] = MiniTest.new_set()

local function sample_ctx()
  return {
    node = { type = "file", path = "/project/lua/init.lua" },
    relative_path = "lua/init.lua",
    ref = "main",
    ref_kind = "branch",
    remote_url = "git@github.com:foo/bar.git",
    host = "github.com",
    owner = "foo",
    repo = "bar",
    kind = "blob",
  }
end

T["build_url"]["uses_builtin_when_builder_nil"] = function()
  local m = load()
  local url = m.build_url(sample_ctx(), { ref = "branch", url_builder = nil })
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/lua/init.lua")
end

T["build_url"]["uses_builder_return_when_string"] = function()
  local m = load()
  local config = {
    ref = "branch",
    url_builder = function(_)
      return "https://custom.example.com/x"
    end,
  }
  MiniTest.expect.equality(m.build_url(sample_ctx(), config), "https://custom.example.com/x")
end

T["build_url"]["falls_back_when_builder_returns_nil"] = function()
  local m = load()
  local config = {
    ref = "branch",
    url_builder = function(_)
      return nil
    end,
  }
  MiniTest.expect.equality(m.build_url(sample_ctx(), config), "https://github.com/foo/bar/blob/main/lua/init.lua")
end

T["build_url"]["falls_back_when_builder_raises"] = function()
  local m = load()
  local notify_msgs = {}
  local original_notify = vim.notify
  vim.notify = function(msg, _)
    table.insert(notify_msgs, msg)
  end
  local config = {
    ref = "branch",
    url_builder = function(_)
      error("boom")
    end,
  }
  local ok, url = pcall(m.build_url, sample_ctx(), config)
  vim.notify = original_notify
  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/lua/init.lua")
  MiniTest.expect.equality(#notify_msgs >= 1, true)
end

T["build_url"]["falls_back_when_builder_returns_non_string"] = function()
  local m = load()
  local notify_msgs = {}
  local original_notify = vim.notify
  vim.notify = function(msg, _)
    table.insert(notify_msgs, msg)
  end
  local config = {
    ref = "branch",
    url_builder = function(_)
      return 42
    end,
  }
  local url = m.build_url(sample_ctx(), config)
  vim.notify = original_notify
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/lua/init.lua")
  MiniTest.expect.equality(#notify_msgs >= 1, true)
end

T["build_url"]["falls_back_when_builder_returns_empty_string"] = function()
  local m = load()
  local notify_msgs = {}
  local original_notify = vim.notify
  vim.notify = function(msg, _)
    table.insert(notify_msgs, msg)
  end
  local config = {
    ref = "branch",
    url_builder = function(_)
      return ""
    end,
  }
  local url = m.build_url(sample_ctx(), config)
  vim.notify = original_notify
  MiniTest.expect.equality(url, "https://github.com/foo/bar/blob/main/lua/init.lua")
  MiniTest.expect.equality(#notify_msgs >= 1, true)
end

T["build_url"]["ctx_table_schema_snapshot"] = function()
  local m = load()
  local captured = nil
  local config = {
    ref = "branch",
    url_builder = function(c)
      captured = c
      return nil
    end,
  }
  m.build_url(sample_ctx(), config)
  MiniTest.expect.equality(type(captured), "table")
  local keys = {}
  for k in pairs(captured) do
    table.insert(keys, k)
  end
  table.sort(keys)
  MiniTest.expect.equality(keys, {
    "host",
    "kind",
    "node",
    "owner",
    "ref",
    "ref_kind",
    "relative_path",
    "remote_url",
    "repo",
  })
end

-----------------------------------------------------------
-- MSG table existence
-----------------------------------------------------------
T["MSG"] = MiniTest.new_set()

T["MSG"]["exposes_required_keys"] = function()
  local m = load()
  local required = {
    "untracked",
    "added",
    "ignored",
    "multi_target",
    "no_remote",
    "no_repo",
    "loading",
    "no_resolvable_ref",
    "unparseable_remote",
    "url_builder_error",
    "timeout",
  }
  for _, key in ipairs(required) do
    MiniTest.expect.equality(type(m.MSG[key]), "string")
  end
end

return T
