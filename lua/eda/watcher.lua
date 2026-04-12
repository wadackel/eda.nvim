local util = require("eda.util")

---@class eda.Watcher
---@field _handles table<string, uv.uv_fs_event_t>
---@field _debounced table<string, fun()>
---@field pending_operations table<string, boolean>
local Watcher = {}
Watcher.__index = Watcher

---Create a new watcher manager.
---@return eda.Watcher
function Watcher.new()
  return setmetatable({
    _handles = {},
    _debounced = {},
    pending_operations = {},
  }, Watcher)
end

---Watch a directory for changes.
---@param path string Directory to watch
---@param callback fun(filename: string, events: table)
function Watcher:watch(path, callback)
  if self._handles[path] then
    return -- Already watching
  end

  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local debounced = util.debounce(50, function(filename, events)
    -- Check if this is an echo from our own operation
    local full_path = path .. "/" .. (filename or "")
    if self.pending_operations[full_path] then
      return
    end
    callback(filename, events)
  end)

  self._debounced[path] = debounced

  handle:start(path, {}, function(err, filename, events)
    if err then
      return
    end
    vim.schedule(function()
      debounced(filename, events)
    end)
  end)

  self._handles[path] = handle
end

---Stop watching a specific path.
---@param path string
function Watcher:unwatch(path)
  local handle = self._handles[path]
  if handle then
    handle:stop()
    handle:close()
    self._handles[path] = nil
    self._debounced[path] = nil
  end
end

---Stop all watchers.
function Watcher:unwatch_all()
  for path, handle in pairs(self._handles) do
    handle:stop()
    handle:close()
    self._handles[path] = nil
    self._debounced[path] = nil
  end
end

---Add a pending operation (suppress watcher echo).
---@param path string
function Watcher:add_pending(path)
  self.pending_operations[path] = true
end

---Remove a pending operation.
---@param path string
function Watcher:remove_pending(path)
  self.pending_operations[path] = nil
end

return Watcher
