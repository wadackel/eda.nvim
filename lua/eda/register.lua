local M = {}

---@class eda.Register
---@field paths string[]
---@field operation "cut"|"copy"

---@type eda.Register?
local register = nil

---Set the register with paths and operation type.
---@param paths string[]
---@param operation "cut"|"copy"
function M.set(paths, operation)
  register = { paths = paths, operation = operation }
end

---Get the current register contents.
---@return eda.Register?
function M.get()
  return register
end

---Clear the register.
function M.clear()
  register = nil
end

---Check if a path is in the register.
---@param path string
---@return boolean
function M.has(path)
  if not register then
    return false
  end
  for _, p in ipairs(register.paths) do
    if p == path then
      return true
    end
  end
  return false
end

---Check if a path is in the register and the operation is cut.
---@param path string
---@return boolean
function M.is_cut(path)
  return register ~= nil and register.operation == "cut" and M.has(path)
end

return M
