local M = {}

local is_mac = vim.uv.os_uname().sysname == "Darwin"

---Debounce a function call.
---@param ms integer Delay in milliseconds
---@param fn fun(...: any) Function to debounce
---@return fun(...: any) debounced Debounced function
function M.debounce(ms, fn)
  local timer = assert(vim.uv.new_timer(), "failed to create timer")
  return function(...)
    local args = { ... }
    timer:stop()
    timer:start(ms, 0, function()
      timer:stop()
      vim.schedule(function()
        ---@diagnostic disable-next-line: deprecated
        fn(unpack(args))
      end)
    end)
  end
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
