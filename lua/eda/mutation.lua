local Fs = require("eda.fs")

local M = {}

local function emit(pattern, data)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = pattern, data = data })
  if not ok then
    vim.notify("eda: mutation hook failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

---@param operations eda.Operation[]
---@param opts eda.ExecuteOptions
---@param cb fun(result: eda.ExecuteResult)
function M.execute(operations, opts, cb)
  if #operations == 0 then
    cb({ completed = {} })
    return
  end
  emit("EdaMutationPre", { operations = operations })
  Fs.execute_operations(operations, opts, function(result)
    -- Tying delivery to a rescan or a live buffer loses completed mutations after close.
    emit("EdaMutationPost", { operations = operations, results = result })
    cb(result)
  end)
end

return M
