local M = {}

---Create a temporary directory for testing.
---@return string path The absolute path to the temporary directory
function M.create_temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

---Remove a temporary directory and all its contents.
---@param path string
function M.remove_temp_dir(path)
  vim.fn.delete(path, "rf")
end

---Wait for a condition to become true, with timeout.
---@param timeout_ms integer Maximum wait time in milliseconds
---@param condition fun(): boolean Function that returns true when condition is met
---@return boolean ok True if condition was met before timeout
function M.wait_for(timeout_ms, condition)
  return vim.wait(timeout_ms, condition, 10)
end

---Create a file with optional content.
---@param path string
---@param content? string
function M.create_file(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local f = io.open(path, "w")
  if f then
    f:write(content or "")
    f:close()
  end
end

---Create a directory.
---@param path string
function M.create_dir(path)
  vim.fn.mkdir(path, "p")
end

return M
