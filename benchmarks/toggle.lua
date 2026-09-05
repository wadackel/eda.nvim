vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to a 100 x 100 file fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT to the output JSON path")
local counts, active, ex = {}, false, nil
local api = vim.api
local set_mark, clear, provider =
  api.nvim_buf_set_extmark, api.nvim_buf_clear_namespace, api.nvim_set_decoration_provider
api.nvim_buf_set_extmark = function(buf, ns, ...)
  if active and ex and ns == ex.buffer.painter.ns_icon then
    counts.icon_writes = counts.icon_writes + 1
  end
  return set_mark(buf, ns, ...)
end
api.nvim_buf_clear_namespace = function(buf, ns, ...)
  if active and ex and ns == ex.buffer.painter.ns_icon then
    counts.icon_clears = counts.icon_clears + 1
  end
  return clear(buf, ns, ...)
end
api.nvim_set_decoration_provider = function(ns, opts)
  if opts.on_line then
    local on_line = opts.on_line
    opts.on_line = function(...)
      if active then
        counts.visible_lines = counts.visible_lines + 1
      end
      return on_line(...)
    end
  end
  return provider(ns, opts)
end
local Chain = require("eda.render.decorator").Chain
local decorate = Chain.decorate
Chain.decorate = function(self, rows, ctx)
  if active then
    counts.decorated_rows = counts.decorated_rows + #rows
  end
  return decorate(self, rows, ctx)
end
local Painter = require("eda.render.painter")
local resync = Painter._resync_on_redraw
Painter._resync_on_redraw = function(self)
  local start = vim.uv.hrtime()
  resync(self)
  if active then
    counts.resync_ms = counts.resync_ms + (vim.uv.hrtime() - start) / 1e6
    counts.resync_calls = counts.resync_calls + 1
  end
end
local function run()
  if #api.nvim_list_uis() == 0 then
    vim.o.lines = 40
    vim.o.columns = 140
  end
  local eda = require("eda")
  eda.setup({
    git = { enabled = false },
    header = false,
    confirm = false,
    window = { kind = "replace" },
    icon = {
      provider = "none",
      custom = function(_, node)
        if node.type == "file" then
          return "f", "EdaFileIcon"
        end
      end,
      directory = { collapsed = "+", expanded = "-", empty = "+", empty_open = "-" },
    },
  })
  eda.open({ dir = fixture })
  assert(
    vim.wait(10000, function()
      return eda.get_current() and eda.get_current()._initial_scan_complete
    end, 1),
    "initial scan timeout"
  )
  ex = eda.get_current()
  local ctx = {
    explorer = ex,
    store = ex.store,
    scanner = ex.scanner,
    buffer = ex.buffer,
    window = ex.window,
    config = require("eda.config").get(),
  }
  local action = require("eda.action")
  action.dispatch("expand_all", ctx)
  assert(
    vim.wait(10000, function()
      return #ex.buffer.flat_lines == 10100
    end, 1),
    "expand timeout"
  )
  local target = ex.buffer.flat_lines[1].node
  local all_lines = #ex.buffer.flat_lines
  assert(target.type == "directory", "Expected the first row to be a directory")
  local child_count = #target.children_ids
  assert(child_count == 100, "Expected 100 files in the first directory")
  local render = ex.buffer.render
  ex.buffer.render = function(self, ...)
    local start = vim.uv.hrtime()
    render(self, ...)
    if active then
      counts.render_ms = counts.render_ms + (vim.uv.hrtime() - start) / 1e6
    end
  end
  local function toggle(open)
    counts = {
      icon_writes = 0,
      icon_clears = 0,
      decorated_rows = 0,
      visible_lines = 0,
      resync_ms = 0,
      resync_calls = 0,
      render_ms = 0,
    }
    api.nvim_win_set_cursor(ex.window.winid, { 1, 0 })
    local start = vim.uv.hrtime()
    action.dispatch("select", ctx)
    local expected = open and all_lines or all_lines - child_count
    assert(
      vim.wait(10000, function()
        return #ex.buffer.flat_lines == expected
      end, 1),
      "toggle timeout"
    )
    vim.cmd("redraw")
    counts.total_ms = (vim.uv.hrtime() - start) / 1e6
    counts.direction = open and "expand" or "collapse"
    return vim.deepcopy(counts)
  end
  local result = { ui = api.nvim_list_uis(), version = vim.version(), fixture = fixture, samples = {} }
  for repetition = 1, 5 do
    active = false
    for _ = 1, 5 do
      toggle(false)
      toggle(true)
    end
    active = true
    for _ = 1, 20 do
      local collapse, expand = toggle(false), toggle(true)
      collapse.repetition, expand.repetition = repetition, repetition
      result.samples[#result.samples + 1] = collapse
      result.samples[#result.samples + 1] = expand
    end
  end
  active = false
  result.screen = {}
  for row = 1, math.min(10, vim.o.lines) do
    local line = {}
    for col = 1, math.min(80, vim.o.columns) do
      line[#line + 1] = vim.fn.screenstring(row, col)
    end
    result.screen[#result.screen + 1] = table.concat(line)
  end
  vim.fn.writefile({ vim.json.encode(result) }, output)
  eda.close()
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    vim.fn.writefile({ tostring(err) }, output .. ".error")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end)
