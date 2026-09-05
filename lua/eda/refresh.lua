local config = require("eda.config")
local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local util = require("eda.util")
local git = require("eda.git")

---@class eda.Refresh
---@field explorer eda.Explorer
---@field pending boolean
---@field running boolean
---@field epoch integer
---@field paths table<string, boolean>
---@field full boolean
---@field _scheduled boolean
local Refresh = {}
Refresh.__index = Refresh

---@param explorer eda.Explorer
---@return eda.Refresh
function Refresh.new(explorer)
  local self = setmetatable(
    { explorer = explorer, pending = false, running = false, epoch = 0, paths = {}, full = false, _scheduled = false },
    Refresh
  )
  local function flush_later()
    if self.pending then
      -- Flushing synchronously would see the temporary clean state before edit replay.
      vim.schedule(function()
        self:flush()
      end)
    end
  end
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = explorer.buffer.bufnr,
    callback = flush_later,
  })
  local option_event = vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "modified",
    callback = flush_later,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = explorer.buffer.bufnr,
    callback = function()
      self:reset()
      explorer.watcher:unwatch_all()
      vim.api.nvim_del_autocmd(option_event)
    end,
  })
  return self
end

function Refresh:reset()
  self.epoch = self.epoch + 1
  self.pending = false
  self.running = false
  self.paths = {}
  self.full = false
  self._scheduled = false
end

---@param path string
---@return string?
function Refresh:directory_for(path)
  local ex = self.explorer
  while path == ex.root_path or path:sub(1, #ex.root_path + 1) == ex.root_path .. "/" or ex.root_path == "/" do
    local node = ex.store:get_by_path(path)
    if node and node.type == "directory" and (node.children_state == "loaded" or node.children_ids ~= nil) then
      return node.path
    end
    local parent = vim.fn.fnamemodify(path, ":h")
    if parent == path then
      break
    end
    path = parent
  end
end

---@param path? string
function Refresh:request(path)
  self.pending = true
  local directory = path and self:directory_for(path)
  if directory then
    self.paths[directory] = true
  else
    self.full = true
  end
  if not self._scheduled then
    self._scheduled = true
    local epoch = self.epoch
    vim.schedule(function()
      if self.epoch == epoch then
        self._scheduled = false
        self:flush()
      end
    end)
  end
end

---@param result eda.ExecuteResult
function Refresh:after_mutation(result)
  local operations = vim.list_extend({}, result.completed)
  if result.failed then
    operations[#operations + 1] = result.failed
  end
  for _, op in ipairs(operations) do
    local paths = op.src and { op.src, op.dst } or { op.path }
    for _, path in ipairs(paths) do
      local directory = self:directory_for(vim.fn.fnamemodify(path, ":h"))
      if directory then
        self:request(directory)
      end
    end
  end
end

function Refresh:sync_watchers()
  local ex = self.explorer
  if not util.is_valid_buf(ex.buffer.bufnr) then
    return
  end
  local wanted = { [ex.root_path] = true }
  for _, line in ipairs(ex.buffer.flat_lines) do
    local node = line.node
    if node.type == "directory" and node.open and node.children_state == "loaded" then
      wanted[node.path] = true
    end
  end
  for path in pairs(ex.watcher._handles) do
    if not wanted[path] then
      ex.watcher:unwatch(path)
      local node = ex.store:get_by_path(path)
      if node then
        -- Collapsed directories have no watch coverage and must be checked on expansion.
        node.children_state = "unloaded"
      end
    end
  end
  local generation = ex.generation
  for path in pairs(wanted) do
    if not ex.watcher._handles[path] then
      ex.watcher:watch(path, function(filename)
        if ex.generation ~= generation or not util.is_valid_buf(ex.buffer.bufnr) then
          return
        end
        self:request(filename and vim.fn.fnamemodify(path .. "/" .. filename, ":h") or nil)
      end)
    end
  end
end

local function child_fields(node)
  return {
    name = node.name,
    path = node.path,
    type = node.type,
    link_target = node.link_target,
    link_broken = node.link_broken,
    error = node.error,
    open = node.open,
    _marked = node._marked,
  }
end

function Refresh:flush()
  local ex = self.explorer
  local bufnr = ex.buffer.bufnr
  if not self.pending or self.running or not util.is_valid_buf(bufnr) then
    return
  end
  if vim.bo[bufnr].modified or ex._writing or not ex._initial_scan_complete or ex.scanner._active_fds > 0 then
    return
  end

  local paths, full = self.paths, self.full
  self.paths, self.full = {}, false
  self.pending = false
  self.running = true
  local epoch, generation, render_gen = self.epoch, ex.generation, ex._render_gen
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local store = ex.store
  local next_id, store_gen = store.next_id, store.generation
  local candidate = Store.new()
  candidate:set_root(ex.root_path)
  local cfg = config.get()
  local scanner = Scanner.new(candidate, cfg)
  local roots = {}

  local function commit()
    if self.epoch ~= epoch then
      return
    end
    self.running = false
    if ex.generation ~= generation or not util.is_valid_buf(bufnr) then
      return
    end
    if
      vim.bo[bufnr].modified
      or ex._writing
      or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick
      or ex._render_gen ~= render_gen
      or store.next_id ~= next_id
      or store.generation ~= store_gen
      or ex.scanner._active_fds > 0
    then
      self.pending = true
      self.full = self.full or full
      for path in pairs(paths) do
        self.paths[path] = true
      end
      self:flush()
      return
    end

    local changed = false
    local function adopt(id)
      local source = candidate:get(id)
      local target = source and store:get_by_path(source.path)
      if not source or not target or target.type ~= "directory" or source.children_state ~= "loaded" then
        return
      end
      local entries = {}
      for _, child_id in ipairs(source.children_ids or {}) do
        entries[#entries + 1] = child_fields(candidate:get(child_id))
      end
      changed = store:reconcile_children(target.id, entries) or changed
      for _, child_id in ipairs(source.children_ids or {}) do
        adopt(child_id)
      end
    end
    for _, id in ipairs(roots) do
      adopt(id)
    end
    if changed then
      ex.buffer:render(store)
    else
      self:sync_watchers()
    end
    if cfg.git.enabled then
      git.status(ex.root_path, function()
        if self.epoch == epoch and ex.generation == generation and util.is_valid_buf(bufnr) then
          ex.buffer:render(store)
        end
      end)
    end
    self:flush()
  end

  -- Applying I/O results directly would replace IDs underneath pending buffer edits.
  if full then
    roots[1] = candidate.root_id
    scanner:rescan_preserving_state(candidate.root_id, commit, store)
    return
  end

  local directories = vim.tbl_keys(paths)
  table.sort(directories, function(a, b)
    return #a < #b
  end)
  for _, path in ipairs(directories) do
    roots[#roots + 1] = path == ex.root_path and candidate.root_id
      or candidate:add({ name = vim.fn.fnamemodify(path, ":t"), path = path, type = "directory" })
  end
  local remaining = #roots
  if remaining == 0 then
    commit()
    return
  end
  for _, id in ipairs(roots) do
    scanner:scan(id, function()
      remaining = remaining - 1
      if remaining == 0 then
        commit()
      end
    end)
  end
end

return Refresh
