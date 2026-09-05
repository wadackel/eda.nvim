local M = { revision = "59f09943573c5348ca6c88393fa09ce3b66a7818" }

local function git(path, operation, ...)
  local command = { "git", "-C", path, operation, ... }
  local ok, result = pcall(function()
    return vim.system(command, { text = true }):wait(60000)
  end)
  local failure = "mini.nvim bootstrap git " .. operation .. " failed at " .. path
  if not ok then
    error(failure .. ": " .. tostring(result), 0)
  end
  if result.code ~= 0 then
    local detail = result.stderr ~= "" and result.stderr or result.stdout
    error(failure .. " (exit " .. result.code .. "): " .. (detail or ""), 0)
  end
  return vim.trim(result.stdout or "")
end

local function validate(path, revision)
  local function invalid(reason)
    error(
      "Invalid mini.nvim cache at "
        .. path
        .. ": "
        .. reason
        .. ". Inspect and move this directory aside, then rerun the tests.",
      0
    )
  end
  local directory = vim.uv.fs_lstat(path)
  local metadata = vim.uv.fs_lstat(path .. "/.git")
  if not directory or directory.type ~= "directory" or not metadata or metadata.type ~= "directory" then
    invalid("expected a complete Git checkout")
  end
  local entrypoint = vim.uv.fs_lstat(path .. "/lua/mini/test.lua")
  if not entrypoint or entrypoint.type ~= "file" then
    invalid("missing lua/mini/test.lua")
  end
  local head = git(path, "rev-parse", "HEAD")
  if head ~= revision then
    invalid("expected " .. revision .. ", found " .. head)
  end
  if git(path, "status", "--porcelain=v1", "--untracked-files=all") ~= "" then
    invalid("working tree contains local changes")
  end
end

---@param opts? { root?: string, repository?: string, revision?: string }
---@return string
function M.ensure(opts)
  opts = opts or {}
  local revision = opts.revision or M.revision
  assert(#revision == 40 and revision:match("^%x+$"), "mini.nvim revision must be a full 40-character commit hash")
  local root = opts.root or (vim.fn.stdpath("data") .. "/eda-test-deps")
  local path = root .. "/mini.nvim-" .. revision
  if vim.uv.fs_lstat(path) then
    validate(path, revision)
    return path
  end

  -- mkdir(..., "p") can still raise EEXIST when another process creates the directory concurrently.
  local created, create_err = pcall(vim.fn.mkdir, root, "p")
  local root_stat = vim.uv.fs_stat(root)
  if not created and (not root_stat or root_stat.type ~= "directory") then
    error("mini.nvim bootstrap cannot create cache root: " .. tostring(create_err), 0)
  end
  local staging, staging_err = vim.uv.fs_mkdtemp(root .. "/.mini.nvim-" .. revision .. "-XXXXXX")
  assert(staging, "mini.nvim bootstrap cannot create staging directory: " .. tostring(staging_err))
  local ok, result = pcall(function()
    git(staging, "init", "--quiet")
    git(
      staging,
      "fetch",
      "--quiet",
      "--depth=1",
      opts.repository or "https://github.com/echasnovski/mini.nvim",
      revision
    )
    git(staging, "checkout", "--quiet", "--detach", "FETCH_HEAD")
    validate(staging, revision)
    if vim.uv.fs_lstat(path) then
      validate(path, revision)
      return path
    end
    -- Publishing before checkout finishes lets another runner accept a partial dependency.
    local published, publish_err = vim.uv.fs_rename(staging, path)
    if not published then
      if not vim.uv.fs_lstat(path) then
        error("mini.nvim bootstrap cannot publish checkout: " .. tostring(publish_err), 0)
      end
      validate(path, revision)
    end
    return path
  end)
  if vim.uv.fs_lstat(staging) then
    vim.fn.delete(staging, "rf")
  end
  if not ok then
    error(result, 0)
  end
  return result
end

return M
