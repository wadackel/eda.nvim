local M = {}

---@class eda.GitCacheEntry
---@field statuses? table<string, string>  -- path → porcelain code after propagation
---@field reported? table<string, true>    -- directly reported changed files only (before propagation)
---@field ready "loading"|"ready"|"no_repo"|"error"

---@type table<string, eda.GitCacheEntry>
local cache = {}

-- Cache for vim.fs.root lookups (root_path → git_root or false)
---@type table<string, string|false>
local _root_cache = {}

---Whether a porcelain status code counts as a "change" for navigation/filter.
---Exclude-list: only `!` (ignored) and space return false.
---@param code string
---@return boolean
local function is_changed_status(code)
  return code ~= "!" and code ~= " "
end

-- Priority for directory status propagation (higher value wins).
local status_priority = {
  ["!"] = 1,
  ["?"] = 2,
  ["A"] = 3,
  ["R"] = 3,
  ["C"] = 3,
  ["M"] = 4,
  ["D"] = 4,
  ["U"] = 5,
}

---Get the parent directory of an absolute path (pure Lua, avoids vim.fn boundary).
---@param path string
---@return string
local function parent_dir(path)
  return path:match("^(.*)/[^/]*$") or path
end

---@param output string
---@param root string Git root directory
---@param reported_out? table<string, true>  Optional set to populate with reported changed paths
---@return table<string, string>
local function parse_status(output, root, reported_out)
  local result = {}
  local records = output:gmatch("([^%z]+)%z")
  for record in records do
    local status_code = record:sub(1, 2)
    local path = record:sub(4)

    -- Arrows and newlines are literal pathname bytes; -z puts rename/copy sources in the next field.
    if status_code:find("[RC]") then
      records()
    end

    -- Determine the effective status
    local idx = status_code:sub(1, 1)
    local wt = status_code:sub(2, 2)
    local effective = wt ~= " " and wt or idx

    -- Strip trailing slash (git --ignored=matching appends "/" to directories)
    path = path:gsub("/$", "")

    local abs_path = root .. "/" .. path
    local existing = result[abs_path]
    if not existing or (status_priority[effective] or 0) > (status_priority[existing] or 0) then
      result[abs_path] = effective
    end

    -- Record directly reported non-ignored entries for jump/filter features.
    -- `--ignored=matching` reports ignored directory entries too; those are excluded
    -- because is_changed_status("!") is false.
    if reported_out and is_changed_status(effective) then
      reported_out[abs_path] = true
    end

    -- Propagate status to parent directories (highest priority wins)
    -- Skip propagation for ignored status — only the directly reported entry should be styled
    if effective ~= "!" then
      local dir = parent_dir(abs_path)
      while dir ~= root and #dir > #root do
        existing = result[dir]
        if not existing or (status_priority[effective] or 0) > (status_priority[existing] or 0) then
          result[dir] = effective
        end
        dir = parent_dir(dir)
      end
    end
  end
  return result
end

---Resolve git root with caching.
---@param root string
---@return string?
local function find_git_root(root)
  local cached = _root_cache[root]
  if cached ~= nil then
    return cached or nil
  end
  local git_root = vim.fs.root(root, ".git")
  _root_cache[root] = git_root or false
  return git_root
end

---Public alias for find_git_root.
---@param root string
---@return string?
function M.find_git_root(root)
  return find_git_root(root)
end

---@class eda.GitRequest
---@field epoch integer
---@field callbacks fun(status: table<string, string>?)[]
---@field finished? boolean

---@class eda.GitRequestSlot
---@field epoch integer
---@field active? eda.GitRequest
---@field pending? eda.GitRequest

---@type table<string, eda.GitRequestSlot>
local requests = {}

---@param request eda.GitRequest
---@param statuses? table<string, string>
local function deliver(request, statuses)
  local callbacks = request.callbacks
  request.callbacks = {}
  for _, callback in ipairs(callbacks) do
    local ok, err = pcall(callback, statuses)
    if not ok then
      vim.schedule(function()
        vim.notify("eda: Git status callback failed: " .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end
end

---@type fun(root: string, slot: eda.GitRequestSlot)
local start_pending

---@param root string
---@param slot eda.GitRequestSlot
local function schedule_pending(root, slot)
  local pending = slot.pending
  if not pending or slot.active then
    return
  end
  vim.schedule(function()
    if slot.pending == pending and not slot.active then
      start_pending(root, slot)
    end
  end)
end

start_pending = function(root, slot)
  local request = slot.pending
  if not request then
    return
  end
  slot.pending = nil
  slot.active = request
  local function complete(result)
    if request.finished then
      return
    end
    request.finished = true
    if slot.active ~= request then
      deliver(request)
      return
    end
    slot.active = nil
    local statuses
    if slot.epoch == request.epoch then
      if result.code == 0 then
        local reported = {}
        statuses = parse_status(result.stdout or "", root, reported)
        cache[root] = { statuses = statuses, reported = reported, ready = "ready" }
      elseif not cache[root] or not cache[root].statuses then
        cache[root] = { ready = slot.pending and "loading" or "error" }
      end
    end
    schedule_pending(root, slot)
    deliver(request, statuses)
  end
  local ok = pcall(
    vim.system,
    { "git", "--no-optional-locks", "-C", root, "status", "--porcelain=v1", "-z", "-uall", "--ignored=matching" },
    {},
    function(result)
      vim.schedule(function()
        complete(result)
      end)
    end
  )
  if not ok then
    complete({ code = 1 })
  end
end

---@param root string Root directory path
---@param cb fun(status: table<string, string>?)
function M.status(root, cb)
  local git_root = find_git_root(root)
  if not git_root then
    cache[root] = { ready = "no_repo" }
    cb(nil)
    return
  end
  if not cache[git_root] or not cache[git_root].statuses then
    cache[git_root] = { ready = "loading" }
  end
  local slot = requests[git_root]
  if not slot then
    slot = { epoch = 0 }
    requests[git_root] = slot
  end
  if slot.pending then
    slot.pending.callbacks[#slot.pending.callbacks + 1] = cb
    return
  end
  -- A request after process launch may follow a write that the running command has already missed.
  slot.pending = { epoch = slot.epoch, callbacks = { cb } }
  schedule_pending(git_root, slot)
end

---Get cached git status (synchronous). Returns path→code map for backward compat.
---@param root string
---@return table<string, string>?
function M.get_cached(root)
  local git_root = find_git_root(root)
  if git_root then
    local entry = cache[git_root]
    return entry and entry.statuses or nil
  end
  return nil
end

---Get directly reported changed file paths as a set. Excludes ignored entries
---and dir propagation (file paths only).
---@param root string
---@return table<string, true>?
function M.get_reported_changes(root)
  local git_root = find_git_root(root)
  if git_root then
    local entry = cache[git_root]
    return entry and entry.reported or nil
  end
  return nil
end

---Get the readiness state of the git status cache for a root.
---Returns nil if status() has never been called for this root.
---@param root string
---@return "loading"|"ready"|"no_repo"|"error"|nil
function M.get_status_ready(root)
  local git_root = find_git_root(root)
  if git_root then
    local entry = cache[git_root]
    return entry and entry.ready or nil
  end
  -- Non-git directories are cached under the input root path itself
  local entry = cache[root]
  return entry and entry.ready or nil
end

---Invalidate cached status for a git root.
---@param root string
function M.invalidate(root)
  local git_root = find_git_root(root)
  if git_root then
    cache[git_root] = nil
    local slot = requests[git_root]
    if slot then
      slot.epoch = slot.epoch + 1
      local pending = slot.pending
      slot.pending = nil
      if pending then
        pending.finished = true
        vim.schedule(function()
          deliver(pending)
        end)
      end
    end
  end
  -- Also clear the no_repo entry keyed under the input root path
  cache[root] = nil
  _root_cache[root] = nil
end

---Check whether a path is inside a git-ignored directory.
---Walks up the path hierarchy looking for an ancestor with "!" status.
---@param git_status table<string, string>
---@param path string
---@return boolean
function M.is_gitignored(git_status, path)
  local dir = parent_dir(path)
  while dir ~= path do
    if git_status[dir] == "!" then
      return true
    end
    path = dir
    dir = parent_dir(dir)
  end
  return false
end

M._parse_status = parse_status
M._is_changed_status = is_changed_status

return M
