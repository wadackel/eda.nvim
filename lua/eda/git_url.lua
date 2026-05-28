local M = {}

---@class eda.GitUrlBuildArgs
---@field host string
---@field owner string
---@field repo string
---@field ref string
---@field rel_path string
---@field node_type "file"|"directory"

---@class eda.GitUrlExecResult
---@field stdout string
---@field code integer

M.MSG = {
  untracked = "open_in_browser: file is untracked, not on remote",
  added = "open_in_browser: file is added (staged), not committed yet",
  ignored = "open_in_browser: file is gitignored, not on remote",
  multi_target = "open_in_browser: select a single node (multi-selection is not supported)",
  no_remote = "open_in_browser: cannot find origin remote",
  no_repo = "open_in_browser: not in a git repository",
  loading = "open_in_browser: git status not ready, retry shortly",
  no_resolvable_ref = "open_in_browser: cannot resolve a remote-known ref. Push the branch or set open_in_browser.ref.",
  unparseable_remote = "open_in_browser: cannot parse remote URL. Set open_in_browser.url_builder for custom hosts.",
  url_builder_error = "open_in_browser: url_builder error",
  timeout = "open_in_browser: git command timed out",
}

---@param s string
---@return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Run a git subcommand inside `git_root`. Exposed as a table field for test injection.
--- Synchronous on purpose: action is user-initiated, runs at most ~5 git calls per
--- invocation, and keeps the fallback logic readable. The 2s per-call timeout caps
--- the worst case. On timeout, this function emits MSG.timeout directly so the
--- caller does not need to distinguish hang from other failures.
---@param git_root string
---@param args string[]
---@return eda.GitUrlExecResult
function M._exec(git_root, args)
  local cmd = { "git", "-C", git_root }
  for _, a in ipairs(args) do
    table.insert(cmd, a)
  end
  local result = vim.system(cmd, { text = true, timeout = 2000 }):wait()
  -- vim.system kills the process with SIGKILL (signal 9) when timeout expires.
  if result.signal == 9 then
    vim.notify(M.MSG.timeout, vim.log.levels.ERROR)
  end
  return { stdout = result.stdout or "", code = result.code or 1 }
end

---Percent-encode a URL path segment (RFC 3986 unreserved set is preserved).
---Multi-byte UTF-8 characters are encoded byte-by-byte.
---@param s string
---@return string
local function encode_segment(s)
  return (s:gsub("([^A-Za-z0-9%-._~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

---Encode a path that may contain `/` separators: each segment is encoded; `/` itself is kept.
---@param path string
---@return string
local function encode_path(path)
  if path == "" then
    return ""
  end
  local segs = {}
  for seg in path:gmatch("[^/]+") do
    table.insert(segs, encode_segment(seg))
  end
  return table.concat(segs, "/")
end

---Encode a git ref name. `/` is preserved (branches like `feature/foo` are valid refs).
---@param ref string
---@return string
local function encode_ref(ref)
  return (ref:gsub("([^A-Za-z0-9%-._~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

---Parse a git remote URL into `{host, owner, repo}`.
---Supports ssh://, git@host:, https://, http://, and git:// schemes.
---Strips `.git` suffix and drops port. Returns `nil` for unparseable input.
---@param url string?
---@return {host: string, owner: string, repo: string}?
function M.parse_remote(url)
  if not url or url == "" then
    return nil
  end

  -- ssh://[user@]host[:port]/owner/repo(.git)?
  local rest = url:match("^ssh://(.+)$")
  if rest then
    rest = rest:gsub("^[^@/]+@", "")
    rest = rest:gsub("^([^/]+):%d+/", "%1/")
    local host, owner, repo = rest:match("^([^/]+)/([^/]+)/([^/]+)$")
    if host then
      return { host = host, owner = owner, repo = (repo:gsub("%.git$", "")) }
    end
    return nil
  end

  -- git@host:owner/repo(.git)?
  do
    local host, owner, repo = url:match("^git@([^:]+):([^/]+)/(.+)$")
    if host then
      return { host = host, owner = owner, repo = (repo:gsub("%.git$", "")) }
    end
  end

  -- https?://[user@]?host/owner/repo(.git)?
  do
    local scheme_rest = url:match("^https?://(.+)$")
    if scheme_rest then
      scheme_rest = scheme_rest:gsub("^[^@/]+@", "")
      local host, owner, repo = scheme_rest:match("^([^/]+)/([^/]+)/([^/]+)$")
      if host then
        return { host = host, owner = owner, repo = (repo:gsub("%.git$", "")) }
      end
    end
  end

  -- git://host/owner/repo(.git)?
  do
    local host, owner, repo = url:match("^git://([^/]+)/([^/]+)/([^/]+)$")
    if host then
      return { host = host, owner = owner, repo = (repo:gsub("%.git$", "")) }
    end
  end

  return nil
end

---Fetch the origin remote URL via `git remote get-url origin`.
---@param git_root string
---@return string?
function M.resolve_remote_url(git_root)
  local result = M._exec(git_root, { "remote", "get-url", "origin" })
  if result.code ~= 0 then
    return nil
  end
  local url = trim(result.stdout)
  if url == "" then
    return nil
  end
  return url
end

---Probe `origin/main` and `origin/master` as last-resort default branch fallback.
---@param git_root string
---@return {ref: string, ref_kind: "default_branch"}?
local function resolve_default_branch_probe(git_root)
  local origin_head = M._exec(git_root, { "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
  if origin_head.code == 0 then
    local head = trim(origin_head.stdout)
    local _, branch = head:match("^([^/]+)/(.+)$")
    if branch and branch ~= "" then
      return { ref = branch, ref_kind = "default_branch" }
    end
  end
  for _, name in ipairs({ "main", "master" }) do
    local probe = M._exec(git_root, { "rev-parse", "--verify", "origin/" .. name })
    if probe.code == 0 then
      return { ref = name, ref_kind = "default_branch" }
    end
  end
  return nil
end

---Resolve the ref name to embed in the URL, following the fallback chain:
---  branch → (no upstream or detached) → sha → (unpushed) → default_branch → nil.
---@param git_root string
---@param config_ref "branch"|"sha"|"default_branch"
---@return {ref: string, ref_kind: "branch"|"sha"|"default_branch"}?
function M.resolve_ref(git_root, config_ref)
  if config_ref == "branch" then
    local branch_result = M._exec(git_root, { "rev-parse", "--abbrev-ref", "HEAD" })
    if branch_result.code == 0 then
      local branch = trim(branch_result.stdout)
      if branch ~= "" and branch ~= "HEAD" then
        local upstream = M._exec(git_root, { "rev-parse", "--abbrev-ref", branch .. "@{upstream}" })
        if upstream.code == 0 then
          local up = trim(upstream.stdout)
          local _, remote_branch = up:match("^([^/]+)/(.+)$")
          if remote_branch and remote_branch ~= "" then
            return { ref = remote_branch, ref_kind = "branch" }
          end
        end
      end
    end
    config_ref = "sha"
  end

  if config_ref == "sha" then
    local sha_result = M._exec(git_root, { "rev-parse", "HEAD" })
    if sha_result.code == 0 then
      local sha = trim(sha_result.stdout)
      if sha ~= "" then
        local contains = M._exec(git_root, { "branch", "-r", "--contains", sha })
        if contains.code == 0 and contains.stdout:match("origin/") then
          return { ref = sha, ref_kind = "sha" }
        end
      end
    end
    config_ref = "default_branch"
  end

  if config_ref == "default_branch" then
    return resolve_default_branch_probe(git_root)
  end

  return nil
end

---Compose a GitHub-style URL: `https://<host>/<owner>/<repo>/<kind>/<ref>/<rel_path>`.
---Both `ref` and `rel_path` are encoded per-segment; `/` inside ref names is preserved.
---@param args eda.GitUrlBuildArgs
---@return string
function M.build_github_url(args)
  local kind = (args.node_type == "directory") and "tree" or "blob"
  local encoded_ref = encode_ref(args.ref)
  local encoded_path = encode_path(args.rel_path or "")
  if encoded_path == "" then
    return string.format("https://%s/%s/%s/%s/%s/", args.host, args.owner, args.repo, kind, encoded_ref)
  end
  return string.format("https://%s/%s/%s/%s/%s/%s", args.host, args.owner, args.repo, kind, encoded_ref, encoded_path)
end

---Public URL composer. Applies `url_builder` override with `pcall` safety, otherwise
---falls back to the built-in GitHub URL composer.
---@param ctx eda.OpenInBrowserCtx
---@param config eda.OpenInBrowserConfig
---@return string
function M.build_url(ctx, config)
  local function builtin()
    return M.build_github_url({
      host = ctx.host,
      owner = ctx.owner,
      repo = ctx.repo,
      ref = ctx.ref,
      rel_path = ctx.relative_path,
      node_type = ctx.kind == "tree" and "directory" or "file",
    })
  end

  if config.url_builder == nil then
    return builtin()
  end

  local ok, result = pcall(config.url_builder, ctx)
  if not ok then
    vim.notify(M.MSG.url_builder_error .. ": " .. tostring(result), vim.log.levels.ERROR)
    return builtin()
  end
  if type(result) == "string" then
    if result ~= "" then
      return result
    end
    vim.notify(M.MSG.url_builder_error .. ": empty string returned", vim.log.levels.ERROR)
    return builtin()
  end
  if result ~= nil then
    vim.notify(M.MSG.url_builder_error .. ": expected string, got " .. type(result), vim.log.levels.ERROR)
    return builtin()
  end
  return builtin()
end

return M
