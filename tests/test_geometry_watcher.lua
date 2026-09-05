local config = require("eda.config")
local eda = require("eda")
local helpers = require("helpers")

local T = MiniTest.new_set()

local tmp, captured_on_win, saved

-- The watcher is registered when the first replace explorer opens, so the provider
-- callback is captured by standing in for nvim_set_decoration_provider before that.
-- Same seam as tests/render/test_incremental_icons.lua. The Painter registers its own
-- provider during the same open, so candidates are collected and the geometry one is
-- identified by the side effect only it has rather than by registration order.
local candidates
local function install_capture()
  saved = { provider = vim.api.nvim_set_decoration_provider, schedule = vim.schedule }
  candidates = {}
  captured_on_win = nil
  vim.api.nvim_set_decoration_provider = function(ns, opts)
    if opts and opts.on_win then
      table.insert(candidates, opts.on_win)
    end
    return saved.provider(ns, opts)
  end
end

---Return the captured callback that sets `_owner_signature` on the explorer.
local function geometry_on_win()
  local explorer = eda.get_current()
  for _, on_win in ipairs(candidates) do
    explorer._owner_signature = nil
    on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
    if type(explorer._owner_signature) == "string" then
      explorer._owner_signature = nil
      return on_win
    end
  end
  error("no decoration provider recorded the owner geometry")
end

local function restore()
  vim.api.nvim_set_decoration_provider = saved.provider
  vim.schedule = saved.schedule
end

T["geometry watcher"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup({
        window = { kind = "replace" },
        preview = { enabled = false },
        git = { enabled = false },
        icon = { provider = "none" },
        header = false,
      })
      tmp = helpers.create_temp_dir()
      helpers.create_file(tmp .. "/file.txt", "FILE")
      install_capture()
      eda.open({ dir = tmp })
      helpers.wait_for(3000, function()
        return eda.get_current() ~= nil and eda.get_current()._initial_scan_complete
      end)
    end,
    post_case = function()
      restore()
      eda.close()
      helpers.remove_temp_dir(tmp)
    end,
  },
})

T["geometry watcher"]["a replace explorer registers a geometry-watching provider"] = function()
  local explorer = eda.get_current()
  local on_win = geometry_on_win()
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  MiniTest.expect.equality(type(explorer._owner_signature), "string")
end

T["geometry watcher"]["unchanged owner geometry schedules no repositioning"] = function()
  local explorer = eda.get_current()
  local on_win = geometry_on_win()
  local scheduled = 0
  vim.schedule = function(fn)
    scheduled = scheduled + 1
    return saved.schedule(fn)
  end

  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  MiniTest.expect.equality(scheduled, 1)
  MiniTest.expect.equality(type(explorer._owner_signature), "string")

  -- Nothing about the owner moved, so the second redraw must do no work.
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  MiniTest.expect.equality(scheduled, 1)
end

T["geometry watcher"]["a changed owner geometry schedules repositioning again"] = function()
  local explorer = eda.get_current()
  local on_win = geometry_on_win()
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)

  local scheduled = 0
  vim.schedule = function(fn)
    scheduled = scheduled + 1
    return saved.schedule(fn)
  end
  explorer._owner_signature = "0,0,1,1,0"
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  MiniTest.expect.equality(scheduled, 1)
end

T["geometry watcher"]["another buffer is rejected without touching the window"] = function()
  local explorer = eda.get_current()
  local on_win = geometry_on_win()
  local other = vim.api.nvim_create_buf(false, true)
  local scheduled = 0
  vim.schedule = function(fn)
    scheduled = scheduled + 1
    return saved.schedule(fn)
  end

  MiniTest.expect.equality(on_win(nil, explorer.window.winid, other), false)
  MiniTest.expect.equality(scheduled, 0)
  vim.api.nvim_buf_delete(other, { force = true })
end

T["geometry watcher"]["a global winbar changes the owner signature"] = function()
  local explorer = eda.get_current()
  local on_win = geometry_on_win()
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  local before = explorer._owner_signature

  local saved_winbar = vim.o.winbar
  vim.o.winbar = "BAR"
  on_win(nil, explorer.window.winid, explorer.buffer.bufnr)
  local after = explorer._owner_signature
  vim.o.winbar = saved_winbar

  MiniTest.expect.equality(before ~= after, true)
end

return T
