vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to the Git render fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT to the output JSON path")
local api = vim.api
local counts, active = {}, false
local Chain = require("eda.render.decorator").Chain
local decorate = Chain.decorate
Chain.decorate = function(self, rows, ctx)
  local start = vim.uv.hrtime()
  local result = decorate(self, rows, ctx)
  if active then
    counts.decorate_ms = counts.decorate_ms + (vim.uv.hrtime() - start) / 1e6
  end
  return result
end
local function run()
  if #api.nvim_list_uis() == 0 then
    vim.o.lines = 40
    vim.o.columns = 140
  end
  local eda = require("eda")
  eda.setup({
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
  local cfg = require("eda.config").get()
  local git = require("eda.git")
  eda.open({ dir = fixture })
  assert(
    vim.wait(10000, function()
      return eda.get_current() and eda.get_current()._initial_scan_complete
    end, 1),
    "initial scan timeout"
  )
  local ex = eda.get_current()
  local ctx = {
    explorer = ex,
    store = ex.store,
    scanner = ex.scanner,
    buffer = ex.buffer,
    window = ex.window,
    config = cfg,
  }
  local action = require("eda.action")
  action.dispatch("expand_all", ctx)
  local previous = -1
  assert(
    vim.wait(20000, function()
      if git.get_status_ready(ex.root_path) ~= "ready" then
        return false
      end
      local count = #ex.buffer.flat_lines
      local settled = count == previous
      previous = count
      return settled
    end, 200),
    "expand timeout"
  )
  local target
  for _, fl in ipairs(ex.buffer.flat_lines) do
    if fl.node.name == "src-00" then
      target = fl.node
      break
    end
  end
  assert(target and target.open, "Expected an open src-00 directory")
  local render = ex.buffer.render
  ex.buffer.render = function(self, ...)
    local start = vim.uv.hrtime()
    render(self, ...)
    if active then
      counts.render_ms = counts.render_ms + (vim.uv.hrtime() - start) / 1e6
    end
  end
  local function reset_counts()
    counts = { decorate_ms = 0, render_ms = 0 }
  end
  local function target_row()
    for i, fl in ipairs(ex.buffer.flat_lines) do
      if fl.node_id == target.id then
        return i
      end
    end
  end
  local function toggle(open)
    reset_counts()
    api.nvim_win_set_cursor(ex.window.winid, { target_row(), 0 })
    local start = vim.uv.hrtime()
    action.dispatch("select", ctx)
    assert(
      vim.wait(10000, function()
        return target.open == open
      end, 1),
      "toggle timeout"
    )
    vim.cmd("redraw")
    counts.total_ms = (vim.uv.hrtime() - start) / 1e6
    counts.direction = open and "expand" or "collapse"
    return vim.deepcopy(counts)
  end
  local function full()
    reset_counts()
    local start = vim.uv.hrtime()
    ex.buffer:render(ex.store)
    vim.cmd("redraw")
    counts.total_ms = (vim.uv.hrtime() - start) / 1e6
    counts.direction = "full"
    return vim.deepcopy(counts)
  end
  local result = { ui = api.nvim_list_uis(), version = vim.version(), fixture = fixture, samples = {}, rows = {} }
  for _, show_gitignored in ipairs({ true, false }) do
    cfg.show_gitignored = show_gitignored
    full()
    local mode = show_gitignored and "shown" or "hidden"
    result.rows[mode] = #ex.buffer.flat_lines
    for repetition = 1, 5 do
      active = false
      for _ = 1, 5 do
        full()
        toggle(false)
        toggle(true)
      end
      active = true
      for _ = 1, 20 do
        for _, sample in ipairs({ full(), toggle(false), toggle(true) }) do
          sample.repetition, sample.cursor = repetition, mode
          result.samples[#result.samples + 1] = sample
        end
      end
      active = false
    end
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
