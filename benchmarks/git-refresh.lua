vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to the Git render fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT to the output JSON path")
local api = vim.api
local counts, active = {}, false
local function cpu_ms()
  local usage = vim.uv.getrusage()
  return (usage.utime.sec + usage.stime.sec) * 1e3 + (usage.utime.usec + usage.stime.usec) / 1e3
end
local Painter = require("eda.render.painter")
local paint = Painter.paint
Painter.paint = function(...)
  local start = vim.uv.hrtime()
  local result = paint(...)
  if active then
    counts.paints = counts.paints + 1
    counts.paint_ms = counts.paint_ms + (vim.uv.hrtime() - start) / 1e6
  end
  return result
end
local git = require("eda.git")
local status = git.status
git.status = function(root, cb)
  return status(root, function(...)
    cb(...)
    if active then
      counts.git_results = counts.git_results + 1
    end
  end)
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
  eda.open({ dir = fixture })
  assert(
    vim.wait(10000, function()
      return eda.get_current() and eda.get_current()._initial_scan_complete
    end, 1),
    "initial scan timeout"
  )
  local ex = eda.get_current()
  require("eda.action").dispatch("expand_all", {
    explorer = ex,
    store = ex.store,
    scanner = ex.scanner,
    buffer = ex.buffer,
    window = ex.window,
    config = require("eda.config").get(),
  })
  local previous = -1
  assert(
    vim.wait(20000, function()
      if git.get_status_ready(ex.root_path) ~= "ready" or ex.refresh.pending or ex.refresh.running then
        return false
      end
      local count = #ex.buffer.flat_lines
      local settled = count == previous
      previous = count
      return settled
    end, 200),
    "expand timeout"
  )
  -- A watcher event for a directory whose listing did not change, as a save of an
  -- already modified file produces.
  local directory = ex.root_path .. "/src-00/nested"
  assert(ex.store:get_by_path(directory), "Expected an expanded src-00/nested")
  local function refresh()
    counts = { paints = 0, paint_ms = 0, git_results = 0 }
    active = true
    local cpu_start = cpu_ms()
    local start = vim.uv.hrtime()
    ex.refresh:request(directory)
    assert(
      vim.wait(10000, function()
        return counts.git_results > 0 and not ex.refresh.pending and not ex.refresh.running
      end, 1),
      "refresh timeout"
    )
    vim.cmd("redraw")
    counts.total_ms = (vim.uv.hrtime() - start) / 1e6
    counts.cpu_ms = cpu_ms() - cpu_start
    active = false
    counts.direction = "refresh"
    return vim.deepcopy(counts)
  end
  local result = {
    ui = api.nvim_list_uis(),
    version = vim.version(),
    fixture = fixture,
    rows = #ex.buffer.flat_lines,
    samples = {},
  }
  for repetition = 1, 5 do
    for _ = 1, 5 do
      refresh()
    end
    for _ = 1, 20 do
      local sample = refresh()
      sample.repetition = repetition
      result.samples[#result.samples + 1] = sample
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
