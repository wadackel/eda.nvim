local util = require("eda.util")

---@class eda.Watcher
---@field _handles table<string, uv.uv_fs_event_t>
---@field _debounced table<string, eda.Debounce>
local Watcher = {}
Watcher.__index = Watcher

---Create a new watcher manager.
---@return eda.Watcher
function Watcher.new()
  return setmetatable({
    _handles = {},
    _debounced = {},
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
    callback(filename, events)
  end)

  self._debounced[path] = debounced
  self._handles[path] = handle

  local ok = handle:start(path, {}, function(err, filename, events)
    if err then
      debounced.call(nil, events)
    else
      debounced.call(filename, events)
    end
  end)

  if not ok then
    self:unwatch(path)
  end
end

---Stop watching a specific path.
---@param path string
function Watcher:unwatch(path)
  local debounced = self._debounced[path]
  if debounced then
    debounced.dispose()
    self._debounced[path] = nil
  end
  local handle = self._handles[path]
  if handle then
    handle:stop()
    handle:close()
    self._handles[path] = nil
  end
end

---Stop all watchers.
function Watcher:unwatch_all()
  for path in pairs(self._handles) do
    self:unwatch(path)
  end
end

return Watcher
