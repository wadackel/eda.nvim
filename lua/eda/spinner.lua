---Braille spinner shared by every async indicator so they animate alike.
local M = {}

-- Plain BMP characters (U+2800-U+28FF) so panvimdoc and fixed-width renderers
-- handle them correctly.
M.frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
M.interval_ms = 100

---@class eda.Spinner
---@field start fun() begin ticking on a timer; a no-op while already running
---@field stop fun() stop and release the timer; safe to call twice or from `on_tick`
---@field tick fun() advance one frame and call `on_tick`; what the timer runs, and a test seam
---@field running fun(): boolean

---@param on_tick fun(glyph: string, index: integer)
---@return eda.Spinner
function M.new(on_tick)
  local index = 0
  local timer ---@type uv.uv_timer_t?

  local function tick()
    index = index % #M.frames + 1
    on_tick(M.frames[index], index)
  end

  local function stop()
    if not timer then
      return
    end
    local t = timer
    timer = nil
    t:stop()
    t:close()
  end

  local function start()
    if timer then
      return
    end
    timer = assert(vim.uv.new_timer(), "failed to create timer")
    timer:start(
      M.interval_ms,
      M.interval_ms,
      vim.schedule_wrap(function()
        -- A tick scheduled just before stop() still lands on the main loop
        if timer then
          tick()
        end
      end)
    )
  end

  return {
    start = start,
    stop = stop,
    tick = tick,
    running = function()
      return timer ~= nil
    end,
  }
end

return M
