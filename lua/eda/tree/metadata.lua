---@class eda.MetadataGroup
---@field remaining integer
---@field valid fun(): boolean
---@field callback fun(err?: string)
---@field settled boolean

---@class eda.MetadataJob
---@field group eda.MetadataGroup
---@field fields table
---@field follow boolean

---@class eda.MetadataResolver
---@field _queue eda.MetadataJob[]
---@field _head integer
---@field _active integer
---@field _limit integer
---@field _disposed boolean
---@field _draining boolean
---@field _groups table<eda.MetadataGroup, true>
local Metadata = {}
Metadata.__index = Metadata

---@return eda.MetadataResolver
function Metadata.new()
  return setmetatable({
    _queue = {},
    _head = 1,
    _active = 0,
    _limit = 32,
    _disposed = false,
    _draining = false,
    _groups = {},
  }, Metadata)
end

---@param group eda.MetadataGroup
---@param err? string
function Metadata:_settle(group, err)
  if group.settled then
    return
  end
  group.settled = true
  self._groups[group] = nil
  group.callback(err)
end

---@param method string
---@param path string
---@param callback fun(err?: string, value?: any)
local function request(method, path, callback)
  local settled = false
  local function complete(err, value)
    if settled then
      return
    end
    settled = true
    callback(err, value)
  end
  local ok, req, err = pcall(vim.uv[method], path, vim.schedule_wrap(complete))
  if not ok or not req then
    complete(tostring(ok and err or req))
  end
end

---@param job eda.MetadataJob
function Metadata:_start(job)
  self._active = self._active + 1
  local group, fields = job.group, job.fields
  local function valid()
    return not self._disposed and not group.settled and group.valid()
  end
  local function finish()
    self._active = self._active - 1
    group.remaining = group.remaining - 1
    if not valid() then
      self:_settle(group, "scan cancelled")
    elseif group.remaining == 0 then
      self:_settle(group)
    end
    self:_drain()
  end
  request("fs_realpath", fields.path, function(err, target)
    if not valid() then
      finish()
      return
    end
    fields.link_broken = err ~= nil or target == nil
    fields.link_target = target
    if fields.link_broken or not job.follow then
      finish()
      return
    end
    request("fs_stat", target, function(stat_err, stat)
      if valid() then
        if stat_err or not stat then
          fields.link_target = nil
          fields.link_broken = true
        elseif stat.type == "directory" then
          fields.type = "directory"
        end
      end
      finish()
    end)
  end)
end

function Metadata:_drain()
  if self._draining then
    return
  end
  self._draining = true
  while not self._disposed and self._active < self._limit and self._head <= #self._queue do
    local job = self._queue[self._head]
    self._head = self._head + 1
    if job.group.settled or not job.group.valid() then
      self:_settle(job.group, "scan cancelled")
    else
      self:_start(job)
    end
  end
  if self._head > #self._queue then
    self._queue = {}
    self._head = 1
  end
  self._draining = false
end

---@param children table[]
---@param follow boolean
---@param valid fun(): boolean
---@param callback fun(err?: string)
function Metadata:resolve(children, follow, valid, callback)
  if self._disposed or not valid() then
    callback("scan cancelled")
    return
  end
  local group = { remaining = 0, valid = valid, callback = callback, settled = false }
  for _, fields in ipairs(children) do
    if fields.type == "link" then
      group.remaining = group.remaining + 1
      self._queue[#self._queue + 1] = { group = group, fields = fields, follow = follow }
    end
  end
  if group.remaining == 0 then
    callback()
    return
  end
  self._groups[group] = true
  self:_drain()
end

function Metadata:dispose()
  if self._disposed then
    return
  end
  self._disposed = true
  self._queue = {}
  self._head = 1
  local groups = self._groups
  self._groups = {}
  for group in pairs(groups) do
    self:_settle(group, "scan cancelled")
  end
end

return Metadata
