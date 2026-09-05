vim.o.shadafile = "NONE"
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT")
local uv, api = vim.uv, vim.api
local Store, Scanner = require("eda.tree.store"), require("eda.tree.scanner")
local Painter, Flatten = require("eda.render.painter"), require("eda.render.flatten")
local active, sample, delay = false, {}, 0
local function ms()
  return uv.hrtime() / 1e6
end
for _, name in ipairs({ "fs_realpath", "fs_stat" }) do
  local original = uv[name]
  uv[name] = function(path, callback)
    if not active then
      return original(path, callback)
    end
    local start = ms()
    sample.metadata_calls = sample.metadata_calls + 1
    if callback then
      sample.async_calls = sample.async_calls + 1
      return original(path, function(err, value)
        local function finish()
          sample.metadata_sum_ms = sample.metadata_sum_ms + ms() - start
          callback(err, value)
        end
        if delay > 0 then
          local timer = assert(uv.new_timer(), "Could not allocate benchmark timer")
          timer:start(delay, 0, function()
            timer:close()
            finish()
          end)
        else
          finish()
        end
      end)
    end
    if delay > 0 then
      uv.sleep(delay)
    end
    local result, err = original(path)
    sample.metadata_sum_ms = sample.metadata_sum_ms + ms() - start
    sample.metadata_blocking_ms = sample.metadata_blocking_ms + ms() - start
    return result, err
  end
end
local close = uv.fs_closedir
uv.fs_closedir = function(dir, callback)
  return close(dir, function(...)
    if active then
      sample.enumeration_ms = ms() - sample.start
    end
    callback(...)
  end)
end
local apply = Scanner._apply_entries
Scanner._apply_entries = function(self, ...)
  local start = ms()
  local result = apply(self, ...)
  sample.apply_ms = sample.apply_ms + ms() - start
  return result
end
local reconcile = Store.reconcile_children
Store.reconcile_children = function(self, ...)
  local start = ms()
  local result = reconcile(self, ...)
  sample.materialize_ms = sample.materialize_ms + ms() - start
  return result
end
local function run()
  local samples = {}
  for _, delay_ms in ipairs({ 0, 1 }) do
    delay = delay_ms
    for _, links in ipairs({ 0, 100, 1000 }) do
      for _, follow in ipairs({ true, false }) do
        for repetition = 0, 5 do
          local store = Store.new()
          local root_id = store:set_root(fixture .. "/links-" .. links)
          local scanner = Scanner.new(store, { follow_symlinks = follow })
          sample = {
            start = ms(),
            links = links,
            follow = follow,
            delay_ms = delay,
            repetition = repetition,
            metadata_calls = 0,
            async_calls = 0,
            metadata_sum_ms = 0,
            metadata_blocking_ms = 0,
            apply_ms = 0,
            materialize_ms = 0,
            max_heartbeat_gap_ms = 0,
          }
          local tick = sample.start
          local timer = assert(uv.new_timer(), "Could not allocate benchmark timer")
          local function beat()
            local now = ms()
            sample.max_heartbeat_gap_ms = math.max(sample.max_heartbeat_gap_ms, now - tick)
            tick = now
          end
          timer:start(1, 1, beat)
          active = true
          local done = false
          scanner:scan(root_id, function()
            sample.scan_ms = ms() - sample.start
            beat()
            done = true
          end)
          assert(
            vim.wait(30000, function()
              return done
            end, 1),
            "scan timeout"
          )
          active = false
          timer:stop()
          timer:close()
          local start = ms()
          local children = store:children(root_id)
          sample.sort_ms = ms() - start
          assert(#children == 1000, "Expected 1000 entries")
          local buf = api.nvim_create_buf(false, true)
          local painter = Painter.new(buf)
          local rows = Flatten.flatten(store, root_id)
          start = ms()
          painter:paint(rows)
          sample.paint_ms = ms() - start
          api.nvim_buf_delete(buf, { force = true })
          sample.start = nil
          if repetition > 0 then
            samples[#samples + 1] = sample
          end
        end
      end
    end
  end
  vim.fn.writefile({ vim.json.encode({ version = vim.version(), fixture = fixture, samples = samples }) }, output)
end
local ok, err = xpcall(run, debug.traceback)
if not ok then
  vim.fn.writefile({ tostring(err) }, output .. ".error")
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
