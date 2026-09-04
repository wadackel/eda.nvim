local helpers = require("helpers")

local T = MiniTest.new_set()

T["spinner"] = MiniTest.new_set()

T["spinner"]["shares its frames and interval with the inspect float"] = function()
  local spinner = require("eda.spinner")
  MiniTest.expect.equality(#spinner.frames, 10)
  MiniTest.expect.equality(spinner.interval_ms, 100)
  MiniTest.expect.equality(require("eda.buffer.inspect")._SPINNER_FRAMES == spinner.frames, true)
end

T["spinner"]["tick cycles through the frames starting at the first"] = function()
  local spinner = require("eda.spinner")
  local seen = {}
  local handle = spinner.new(function(glyph, index)
    seen[#seen + 1] = { glyph, index }
  end)
  for _ = 1, 11 do
    handle.tick()
  end
  MiniTest.expect.equality(seen[1], { spinner.frames[1], 1 })
  MiniTest.expect.equality(seen[10], { spinner.frames[10], 10 })
  MiniTest.expect.equality(seen[11], { spinner.frames[1], 1 })
end

T["spinner"]["start and stop are idempotent"] = function()
  local spinner = require("eda.spinner")
  local handle = spinner.new(function() end)
  MiniTest.expect.equality(handle.running(), false)
  handle.start()
  handle.start()
  MiniTest.expect.equality(handle.running(), true)
  handle.stop()
  handle.stop()
  MiniTest.expect.equality(handle.running(), false)
end

T["spinner"]["stop may be called from inside on_tick"] = function()
  local spinner = require("eda.spinner")
  local handle
  handle = spinner.new(function()
    handle.stop()
  end)
  handle.start()
  handle.tick()
  MiniTest.expect.equality(handle.running(), false)
end

T["spinner"]["the timer drives ticks until stopped"] = function()
  local spinner = require("eda.spinner")
  local ticks = 0
  local handle = spinner.new(function()
    ticks = ticks + 1
  end)
  handle.start()
  helpers.wait_for(1000, function()
    return ticks >= 2
  end)
  handle.stop()
  local at_stop = ticks
  vim.wait(250)
  MiniTest.expect.equality(ticks, at_stop)
end

return T
