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
local Refresh = {}
Refresh.__index = Refresh

---@param explorer eda.Explorer
---@return eda.Refresh
function Refresh.new(explorer)
  local self = setmetatable({ explorer = explorer, pending = false, running = false, epoch = 0 }, Refresh)
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
end

function Refresh:request()
  self.pending = true
  self:flush()
end

function Refresh:flush()
  local ex = self.explorer
  local bufnr = ex.buffer.bufnr
  if not self.pending or self.running or not util.is_valid_buf(bufnr) then
    return
  end
  if vim.bo[bufnr].modified or not ex._initial_scan_complete or ex.scanner._active_fds > 0 then
    return
  end

  self.pending = false
  self.running = true
  local epoch, generation, render_gen = self.epoch, ex.generation, ex._render_gen
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local store = ex.store
  local next_id, store_gen = store.next_id, store.generation
  local candidate = Store.new()
  candidate:set_root(ex.root_path)
  candidate.next_id = next_id
  local cfg = config.get()
  local scanner = Scanner.new(candidate, cfg)

  -- Guarding only the watcher event misses edits started during asynchronous I/O.
  -- Applying directory results directly would invalidate the dirty snapshot's IDs.
  scanner:rescan_preserving_state(candidate.root_id, function()
    if self.epoch ~= epoch then
      return
    end
    self.running = false
    if ex.generation ~= generation or not util.is_valid_buf(bufnr) then
      return
    end
    if
      vim.bo[bufnr].modified
      or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick
      or ex._render_gen ~= render_gen
      or store.next_id ~= next_id
      or store.generation ~= store_gen
      or ex.scanner._active_fds > 0
    then
      self.pending = true
      self:flush()
      return
    end

    store.nodes = candidate.nodes
    store.path_index = candidate.path_index
    store.next_id = candidate.next_id
    store:next_generation()
    ex.buffer:render(store)
    if cfg.git.enabled then
      git.status(ex.root_path, function()
        if self.epoch == epoch and ex.generation == generation and util.is_valid_buf(bufnr) then
          ex.buffer:render(store)
        end
      end)
    end
    self:flush()
  end, store)
end

return Refresh
