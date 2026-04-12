local M = {}

---@alias eda.ActionFn fun(ctx: eda.ActionContext)

---@class eda.ActionEntry
---@field fn eda.ActionFn
---@field desc? string

---@class eda.ActionContext
---@field store eda.Store
---@field buffer eda.Buffer
---@field window eda.Window
---@field scanner eda.Scanner
---@field config eda.Config
---@field explorer eda.Explorer

---@type table<string, eda.ActionEntry>
local registry = {}

---Register an action.
---@param name string
---@param fn eda.ActionFn
---@param opts? { desc?: string }
function M.register(name, fn, opts)
  opts = opts or {}
  registry[name] = { fn = fn, desc = opts.desc }
end

---Dispatch an action by name.
---@param name string
---@param ctx eda.ActionContext
function M.dispatch(name, ctx)
  local entry = registry[name]
  if entry then
    entry.fn(ctx)
  end
end

---List all registered action names.
---@return string[]
function M.list()
  local names = {}
  for name, _ in pairs(registry) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

---Get a registered action function.
---@param name string
---@return eda.ActionFn?
function M.get(name)
  local entry = registry[name]
  return entry and entry.fn or nil
end

---Get a registered action entry (with metadata).
---@param name string
---@return eda.ActionEntry?
function M.get_entry(name)
  return registry[name]
end

return M
