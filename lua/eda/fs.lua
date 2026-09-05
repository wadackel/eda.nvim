local M = {}

---Create a file or directory.
---@param path string
---@param is_dir boolean
---@param cb fun(err?: string)
function M.create(path, is_dir, cb)
  vim.schedule(function()
    local parent = vim.fn.fnamemodify(path, ":h")
    local ok, parent_err = pcall(vim.fn.mkdir, parent, "p")
    if not ok then
      cb("Failed to create parent directory: " .. tostring(parent_err))
      return
    end
    if is_dir then
      vim.uv.fs_mkdir(path, 493, function(err)
        vim.schedule(function()
          cb(err and ("Failed to create directory: " .. err) or nil)
        end)
      end)
    else
      -- A preflight check cannot prevent another writer from creating the path before open.
      vim.uv.fs_open(path, "wx", 420, function(err, fd)
        if err then
          vim.schedule(function()
            cb("Failed to create file: " .. err)
          end)
          return
        end
        vim.uv.fs_close(fd, function(close_err)
          vim.schedule(function()
            cb(close_err and ("Failed to close created file: " .. close_err) or nil)
          end)
        end)
      end)
    end
  end)
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
---@param opts? { no_replace?: boolean }
function M.move(src, dst, cb, opts)
  if opts and opts.no_replace then
    require("eda.fs.exclusive").move(src, dst, cb)
    return
  end
  -- Ensure destination parent exists before renaming
  vim.schedule(function()
    local parent = vim.fn.fnamemodify(dst, ":h")
    local ok, parent_err = pcall(vim.fn.mkdir, parent, "p")
    if not ok then
      cb("Failed to create destination parent: " .. tostring(parent_err))
      return
    end
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
---@param opts? { no_replace?: boolean }
function M.copy(src, dst, cb, opts)
  if opts and opts.no_replace then
    require("eda.fs.exclusive").copy(src, dst, cb)
    return
  end
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

---@return string? backend
---@return string? error
function M.trash_backend()
  local backend = vim.uv.os_uname().sysname == "Darwin" and "osascript" or "trash-put"
  if vim.fn.executable(backend) == 1 then
    return backend
  end
  local remedy = backend == "trash-put" and "Install trash-cli (trash-put)" or "Make osascript available"
  return nil, "System trash unavailable: " .. remedy .. "; set delete_to_trash=false only for permanent deletion"
end

---@param path string
---@param cb fun(err?: string)
function M.trash(path, cb)
  if path:find("%c") then
    cb("Path contains unsupported control characters: " .. path)
    return
  end
  local backend, backend_err = M.trash_backend()
  if not backend then
    cb(backend_err)
    return
  end
  local command
  if backend == "osascript" then
    command = {
      backend,
      "-e",
      'on run argv\ntell application "Finder" to delete POSIX file (item 1 of argv)\nend run',
      "--",
      path,
    }
  else
    command = { backend, "--", path }
  end
  local ok, err = pcall(
    vim.system,
    command,
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        local detail = result.stderr ~= "" and result.stderr or ("exit code " .. result.code)
        cb("Failed to trash with " .. backend .. ": " .. detail)
      else
        cb()
      end
    end)
  )
  if not ok then
    cb("Failed to start " .. backend .. ": " .. tostring(err))
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
