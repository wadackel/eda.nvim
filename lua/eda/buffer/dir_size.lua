---Async recursive directory-size calculator with TTL cache.
---
---Contract:
---  Dedup: concurrent ensure(path) calls while a walk is in-flight do not
---  launch a second walk. No-cancel: an in-flight walk always runs to
---  completion (M._clear_cache does not interrupt it). Callback-less: ensure
---  returns a snapshot of current state; callers poll on their own schedule.
---
---Symlink handling: entries reported by fs_readdir with type "link" are
---counted using their own lstat size and the link target is NOT followed.
---This prevents cycles and double-counting of reachable content.

local M = {}

---@class eda.DirSizeEntry
---@field bytes integer
---@field computed_at_ms integer

local _defaults = { cache_ttl_ms = 30000 }
local _config = vim.deepcopy(_defaults)
local _cache = {} ---@type table<string, eda.DirSizeEntry>
local _active = {} ---@type table<string, true>

---@param opts { cache_ttl_ms?: integer }?
function M.setup(opts)
  _config = vim.tbl_extend("force", vim.deepcopy(_defaults), opts or {})
end

---Test-only accessor for the current resolved config snapshot.
---@return { cache_ttl_ms: integer }
function M._get_config()
  return _config
end

---True iff at least one walk is currently in-flight.
---@return boolean
function M.is_computing()
  return next(_active) ~= nil
end

---Drop all cached entries. In-flight walks continue and will repopulate.
---Exposed with a leading underscore to signal test-only / debug usage.
function M._clear_cache()
  _cache = {}
end

---Start an async walk for `path`. Exposed as a module field so tests can
---monkey-patch it for call-count assertions (see test_dir_size.lua).
---@param path string
function M._start_walk(path)
  local state = { bytes = 0, in_flight = 0 }
  local root_errored = false

  local process_dir
  local descend_nested

  local function try_finish()
    if state.in_flight ~= 0 then
      return
    end
    if not root_errored then
      _cache[path] = { bytes = state.bytes, computed_at_ms = vim.uv.now() }
    end
    _active[path] = nil
  end

  process_dir = function(p, dir)
    local function read_batch()
      vim.uv.fs_readdir(dir, function(read_err, ents)
        if read_err or not ents then
          vim.uv.fs_closedir(dir, function()
            vim.schedule(function()
              state.in_flight = state.in_flight - 1
              try_finish()
            end)
          end)
          return
        end
        for _, ent in ipairs(ents) do
          local child = p .. "/" .. ent.name
          if ent.type == "directory" then
            descend_nested(child)
          else
            state.in_flight = state.in_flight + 1
            vim.uv.fs_lstat(child, function(_, stat)
              vim.schedule(function()
                if stat and stat.size then
                  state.bytes = state.bytes + stat.size
                end
                state.in_flight = state.in_flight - 1
                try_finish()
              end)
            end)
          end
        end
        read_batch()
      end)
    end
    read_batch()
  end

  descend_nested = function(p)
    state.in_flight = state.in_flight + 1
    vim.uv.fs_opendir(p, function(err, dir)
      if err or not dir then
        -- Nested error: skip this subtree, continue parent walk.
        vim.schedule(function()
          state.in_flight = state.in_flight - 1
          try_finish()
        end)
        return
      end
      process_dir(p, dir)
    end, 64)
  end

  -- Root
  state.in_flight = state.in_flight + 1
  vim.uv.fs_opendir(path, function(err, dir)
    if err or not dir then
      vim.schedule(function()
        root_errored = true
        state.in_flight = state.in_flight - 1
        try_finish()
      end)
      return
    end
    process_dir(path, dir)
  end, 64)
end

---Snapshot current state for `path`. Starts a walk if cache miss and no
---in-flight walk for the same path.
---@param path string absolute path
---@return { state: "cached"|"computing", bytes: integer? }
function M.ensure(path)
  local c = _cache[path]
  if c and (vim.uv.now() - c.computed_at_ms) < _config.cache_ttl_ms then
    return { state = "cached", bytes = c.bytes }
  end
  if _active[path] then
    return { state = "computing" }
  end
  _active[path] = true
  M._start_walk(path)
  return { state = "computing" }
end

return M
