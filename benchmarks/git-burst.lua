vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to the Git fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT")
local api = vim.api
local function ms()
  return vim.uv.hrtime() / 1e6
end
local sample, active, live = {}, false, 0
local system = vim.system
vim.system = function(command, opts, callback)
  if not vim.tbl_contains(command, "status") then
    return system(command, opts, callback)
  end
  local recorded = active and sample or nil
  live = live + 1
  if recorded then
    recorded.processes = recorded.processes + 1
    recorded.peak_processes = math.max(recorded.peak_processes, live)
  end
  return system(command, opts, function(result)
    live = live - 1
    callback(result)
  end)
end
local git = require("eda.git")
local status = git.status
local last_callback = ms()
git.status = function(root, callback)
  local recorded = active and sample or nil
  if recorded then
    recorded.requests = recorded.requests + 1
  end
  return status(root, function(value)
    callback(value)
    last_callback = ms()
    if recorded then
      recorded.callbacks = recorded.callbacks + 1
      recorded.last_callback = last_callback
    end
  end)
end
local function run()
  local eda = require("eda")
  eda.setup({
    header = false,
    icon = { provider = "none" },
    window = { kind = "split_left" },
    preview = { enabled = false },
    update_focused_file = { enabled = false },
  })
  eda.open({ dir = fixture })
  assert(
    vim.wait(10000, function()
      return eda.get_current()._initial_scan_complete and git.get_status_ready(fixture) == "ready"
    end, 1),
    "open timeout"
  )
  eda.open_split(fixture)
  eda.open_split(fixture)
  local function idle()
    if live ~= 0 or ms() - last_callback < 100 then
      return false
    end
    local all = eda.get_all()
    if #all ~= 3 then
      return false
    end
    for _, ex in ipairs(all) do
      if not ex._initial_scan_complete or ex.refresh.pending or ex.refresh.running or ex.scanner._active_fds > 0 then
        return false
      end
    end
    return true
  end
  assert(vim.wait(10000, idle, 1), "initial idle timeout")
  local buffers = {}
  for i = 1, 25 do
    local buf = vim.fn.bufadd(fixture .. string.format("/file-%04d.txt", i))
    vim.fn.bufload(buf)
    buffers[i] = buf
  end
  local result = { fixture = fixture, version = vim.version(), explorers = 3, saves_per_burst = 25, samples = {} }
  for repetition = 0, 5 do
    sample = { repetition = repetition, processes = 0, peak_processes = 0, requests = 0, callbacks = 0 }
    active = true
    local start = ms()
    for i, buf in ipairs(buffers) do
      api.nvim_buf_set_lines(buf, 0, -1, false, { "saved " .. repetition .. " / " .. i })
      api.nvim_buf_call(buf, function()
        vim.cmd("silent write")
      end)
    end
    local saved = ms()
    assert(
      vim.wait(10000, function()
        return sample.requests >= 3 and sample.callbacks == sample.requests and idle()
      end, 1),
      "save refresh timeout"
    )
    active = false
    local cached = git.get_cached(fixture)
    assert(cached, "Missing final Git status")
    for i = 1, 25 do
      assert(cached[fixture .. string.format("/file-%04d.txt", i)] == "M", "Missing saved file status")
    end
    sample.save_ms = saved - start
    sample.refresh_after_save_ms = sample.last_callback - saved
    sample.total_ms = sample.last_callback - start
    sample.last_callback = nil
    if repetition > 0 then
      result.samples[#result.samples + 1] = sample
    end
  end
  while eda.get_current() do
    eda.close()
  end
  vim.fn.writefile({ vim.json.encode(result) }, output)
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  vim.fn.writefile({ tostring(err) }, output .. ".error")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
