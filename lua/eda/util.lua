local M = {}

local is_mac = vim.uv.os_uname().sysname == "Darwin"

---@class eda.Debounce
---@field call fun(...: any)
---@field cancel fun()
---@field dispose fun()

---@param ms integer Delay in milliseconds
---@param fn fun(...: any) Function to debounce
---@return eda.Debounce
function M.debounce(ms, fn)
  local timer = assert(vim.uv.new_timer(), "failed to create timer")
  local disposed, generation = false, 0
  local function cancel()
    generation = generation + 1
    if not disposed then
      timer:stop()
    end
  end
  local function dispose()
    if disposed then
      return
    end
    cancel()
    disposed = true
    timer:close()
  end
  local function call(...)
    if disposed then
      return
    end
    cancel()
    local token = generation
    local args = { ... }
    local count = select("#", ...)
    timer:start(ms, 0, function()
      vim.schedule(function()
        -- Stopping the timer cannot retract a callback already queued with vim.schedule.
        if not disposed and generation == token then
          ---@diagnostic disable-next-line: deprecated
          fn(unpack(args, 1, count))
        end
      end)
    end)
  end
  return { call = call, cancel = cancel, dispose = dispose }
end

---Check if a buffer is valid.
---@param bufnr integer
---@return boolean
function M.is_valid_buf(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

---Check if a window is valid.
---@param winid integer
---@return boolean
function M.is_valid_win(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

---Normalize a string from NFD to NFC (macOS filesystem compatibility).
---On non-macOS systems, returns the input unchanged.
---@param str string
---@return string
function M.nfc_normalize(str)
  if not is_mac then
    return str
  end
  local result = vim.fn.iconv(str, "utf-8-mac", "utf-8")
  if result == "" and str ~= "" then
    return str
  end
  return result
end

return M
