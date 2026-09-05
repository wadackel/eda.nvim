local util = require("eda.util")
local Watcher = require("eda.watcher")
local Preview = require("eda.preview")
local helpers = require("helpers")
local T = MiniTest.new_set()

local function with_timers(test)
  local original_timer, original_schedule = vim.uv.new_timer, vim.schedule
  local timers, queued = {}, {}
  vim.uv.new_timer = function()
    local timer = { closes = 0, starts = 0, closing = false }
    function timer:start(_, _, callback)
      self.starts = self.starts + 1
      self.fire = callback
    end
    function timer:stop() end
    function timer:close()
      self.closes = self.closes + 1
      self.closing = true
    end
    function timer:is_closing()
      return self.closing
    end
    timers[#timers + 1] = timer
    return timer
  end
  vim.schedule = function(callback)
    queued[#queued + 1] = callback
  end
  local function flush()
    local pending = queued
    queued = {}
    for _, callback in ipairs(pending) do
      callback()
    end
  end
  local ok, err = pcall(test, timers, flush)
  vim.uv.new_timer, vim.schedule = original_timer, original_schedule
  assert(ok, err)
end

T["cancel and dispose are idempotent before the first call"] = function()
  with_timers(function(timers, flush)
    local d = util.debounce(50, function()
      error("unexpected callback")
    end)
    d.cancel()
    d.cancel()
    d.dispose()
    d.dispose()
    d.cancel()
    d.call("late")
    flush()
    MiniTest.expect.equality(timers[1].closes, 1)
    MiniTest.expect.equality(timers[1].starts, 0)
  end)
end

T["cancel invalidates queued work and permits later scheduling with nil arguments"] = function()
  with_timers(function(timers, flush)
    local calls = {}
    local d = util.debounce(50, function(...)
      calls[#calls + 1] = { n = select("#", ...), ... }
    end)
    d.call("old")
    timers[1].fire()
    d.cancel()
    d.cancel()
    flush()
    MiniTest.expect.equality(#calls, 0)
    d.call("new", nil, 3, nil)
    timers[1].fire()
    flush()
    MiniTest.expect.equality(calls, { { n = 4, [1] = "new", [3] = 3 } })
    d.dispose()
  end)
end

T["rescheduling invalidates an already-fired callback"] = function()
  with_timers(function(timers, flush)
    local calls = {}
    local d = util.debounce(50, function(value)
      calls[#calls + 1] = value
    end)
    d.call("old")
    timers[1].fire()
    d.call("new")
    flush()
    MiniTest.expect.equality(#calls, 0)
    timers[1].fire()
    flush()
    MiniTest.expect.equality(calls, { "new" })
    d.dispose()
  end)
end

for _, fired in ipairs({ false, true }) do
  T["dispose invalidates pending work after timer fired=" .. tostring(fired)] = function()
    with_timers(function(timers, flush)
      local d = util.debounce(50, function()
        error("unexpected callback")
      end)
      d.call()
      if fired then
        timers[1].fire()
      end
      d.dispose()
      d.dispose()
      if not fired then
        timers[1].fire()
      end
      flush()
      MiniTest.expect.equality(timers[1].closes, 1)
    end)
  end
end

T["preview close disposes its timer and cancels queued display"] = function()
  with_timers(function(timers, flush)
    local preview = Preview.new({ enabled = true, debounce = 50 })
    preview.show = function()
      error("closed preview was reopened")
    end
    preview:update({ type = "file", path = "/tmp/preview" })
    timers[1].fire()
    preview:close()
    preview:close()
    flush()
    MiniTest.expect.equality(timers[1].closes, 1)
    MiniTest.expect.equality(preview._debounced, nil)
    preview:update({ type = "file", path = "/tmp/next" })
    MiniTest.expect.equality(#timers, 2)
    preview:close()
  end)
end

T["100 watch and unwatch cycles return live handles to baseline"] = function()
  local before, owned = {}, {}
  vim.uv.walk(function(handle)
    before[handle] = true
  end)
  local tmp = helpers.create_temp_dir()
  local watcher = Watcher.new()
  local ok, err = pcall(function()
    for _ = 1, 100 do
      watcher:watch(tmp, function()
        error("stale watcher")
      end)
      watcher:unwatch_all()
    end
    collectgarbage("collect")
    vim.uv.walk(function(handle)
      if not before[handle] then
        owned[handle] = true
      end
    end)
    local live = 0
    helpers.wait_for(1000, function()
      live = 0
      vim.uv.walk(function(handle)
        if owned[handle] then
          live = live + 1
        end
      end)
      return live == 0
    end)
    MiniTest.expect.equality(live, 0)
  end)
  watcher:unwatch_all()
  vim.uv.walk(function(handle)
    if owned[handle] and not handle:is_closing() then
      handle:close()
    end
  end)
  helpers.remove_temp_dir(tmp)
  assert(ok, err)
end

for _, fail_start in ipairs({ false, true }) do
  T["watcher cleanup invalidates queued events with start failure=" .. tostring(fail_start)] = function()
    with_timers(function(timers, flush)
      local original = vim.uv.new_fs_event
      local handle = { closes = 0 }
      function handle:start(_, _, callback)
        self.event = callback
        if fail_start then
          return nil, "ENOENT"
        end
        return 0
      end
      function handle:stop() end
      function handle:close()
        self.closes = self.closes + 1
      end
      vim.uv.new_fs_event = function()
        return handle
      end
      local watcher = Watcher.new()
      local ok, err = pcall(function()
        watcher:watch("/root", function()
          error("stale event")
        end)
        if not fail_start then
          handle.event(nil, "entry", {})
          flush()
          timers[1].fire()
          watcher:unwatch("/root")
          handle.event(nil, "late", {})
          flush()
        end
        MiniTest.expect.equality(next(watcher._handles), nil)
        MiniTest.expect.equality(next(watcher._debounced), nil)
        MiniTest.expect.equality(handle.closes, 1)
        MiniTest.expect.equality(timers[1].closes, 1)
      end)
      watcher:unwatch_all()
      vim.uv.new_fs_event = original
      assert(ok, err)
    end)
  end
end

return T
