local M = {}

---Create a file or directory.
---@param path string
---@param is_dir boolean
---@param cb fun(err?: string)
function M.create(path, is_dir, cb)
  if is_dir then
    vim.uv.fs_mkdir(path, 493, function(err) -- 0755
      if err then
        -- Try mkdir -p equivalent
        vim.schedule(function()
          local ok = vim.fn.mkdir(path, "p")
          cb(ok == 0 and ("Failed to create directory: " .. path) or nil)
        end)
      else
        vim.schedule(function()
          cb()
        end)
      end
    end)
  else
    -- Ensure parent directory exists
    local parent = vim.fn.fnamemodify(path, ":h")
    vim.schedule(function()
      vim.fn.mkdir(parent, "p")
      vim.uv.fs_open(path, "w", 420, function(err, fd) -- 0644
        if err then
          vim.schedule(function()
            cb("Failed to create file: " .. err)
          end)
          return
        end
        vim.uv.fs_close(fd, function()
          vim.schedule(function()
            cb()
          end)
        end)
      end)
    end)
  end
end

---Delete a file or directory recursively.
---@param path string
---@param cb fun(err?: string)
function M.delete(path, cb)
  vim.schedule(function()
    local ok, err = pcall(vim.fs.rm, path, { recursive = true, force = true })
    if not ok then
      cb("Failed to delete: " .. (err or path))
    else
      cb()
    end
  end)
end

---Move/rename a file or directory.
---@param src string
---@param dst string
---@param cb fun(err?: string)
function M.move(src, dst, cb)
  -- Ensure destination parent exists before renaming
  vim.schedule(function()
    local parent = vim.fn.fnamemodify(dst, ":h")
    vim.fn.mkdir(parent, "p")
    vim.uv.fs_rename(src, dst, function(err)
      vim.schedule(function()
        if err then
          cb("Failed to move " .. src .. " → " .. dst .. ": " .. err)
        else
          cb()
        end
      end)
    end)
  end)
end

---Copy a file or directory.
---@param src string
---@param dst string
---@param cb fun(err?: string)
function M.copy(src, dst, cb)
  vim.schedule(function()
    local parent = vim.fn.fnamemodify(dst, ":h")
    vim.fn.mkdir(parent, "p")

    -- Use system cp for recursive copy
    vim.system({ "cp", "-R", src, dst }, {}, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          cb("Failed to copy: " .. (result.stderr or ""))
        else
          cb()
        end
      end)
    end)
  end)
end

---Move a file/directory to system trash (macOS).
---@param path string
---@param cb fun(err?: string)
function M.trash(path, cb)
  if path:find("%c") then
    cb("Path contains unsupported control characters: " .. path)
    return
  end
  local sysname = vim.uv.os_uname().sysname
  if sysname == "Darwin" then
    vim.system({
      "osascript",
      "-e",
      string.format('tell app "Finder" to delete POSIX file "%s"', path:gsub("\\", "\\\\"):gsub('"', '\\"')),
    }, {}, function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          cb("Failed to trash: " .. (result.stderr or ""))
        else
          cb()
        end
      end)
    end)
  else
    -- Fallback: use trash-cli or just delete
    M.delete(path, cb)
  end
end

---@class eda.ExecuteResult
---@field completed eda.Operation[]
---@field failed eda.Operation?
---@field error string?

---Execute a list of operations sequentially. Halts on first error.
---@param operations eda.Operation[]
---@param opts { delete_to_trash: boolean }
---@param cb fun(result: eda.ExecuteResult)
function M.execute_operations(operations, opts, cb)
  local completed = {}
  local idx = 0

  local function next_op()
    idx = idx + 1
    if idx > #operations then
      cb({ completed = completed, failed = nil, error = nil })
      return
    end

    local op = operations[idx]

    local function on_done(err)
      if err then
        -- Format partial failure report
        local msg = ""
        if #completed > 0 then
          local parts = {}
          for _, c in ipairs(completed) do
            if c.type == "move" then
              table.insert(parts, "MOVE " .. c.src .. " → " .. c.dst)
            elseif c.type == "create" then
              table.insert(parts, "CREATE " .. c.path)
            elseif c.type == "delete" then
              table.insert(parts, "DELETE " .. c.path)
            end
          end
          msg = "Completed: " .. table.concat(parts, ", ") .. "\n"
        end
        msg = msg .. "Failed: " .. op.type:upper() .. " " .. (op.path or op.src or "") .. " (" .. err .. ")"
        vim.notify(msg, vim.log.levels.ERROR)
        cb({ completed = completed, failed = op, error = err })
        return
      end

      table.insert(completed, op)
      next_op()
    end

    if op.type == "create" then
      M.create(op.path, op.entry_type == "directory", on_done)
    elseif op.type == "delete" then
      if opts.delete_to_trash then
        M.trash(op.path, on_done)
      else
        M.delete(op.path, on_done)
      end
    elseif op.type == "move" then
      M.move(op.src, op.dst, on_done)
    else
      on_done("Unknown operation type: " .. tostring(op.type))
    end
  end

  next_op()
end

return M
