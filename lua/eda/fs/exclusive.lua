local uv = vim.uv
local M = {}

local function copy_entry(src, dst, callback)
  uv.fs_lstat(src, function(err, stat)
    if err or not stat then
      callback(err or ("Cannot stat source: " .. src))
    elseif stat.type == "link" then
      uv.fs_readlink(src, function(link_err, target)
        if link_err then
          callback(link_err)
        else
          uv.fs_symlink(target, dst, callback)
        end
      end)
    elseif stat.type == "directory" then
      uv.fs_mkdir(dst, 448, function(mkdir_err)
        if mkdir_err then
          callback(mkdir_err)
          return
        end
        uv.fs_scandir(src, function(scan_err, request)
          if scan_err then
            callback(scan_err)
            return
          end
          local names = {}
          while true do
            local name = uv.fs_scandir_next(request)
            if not name then
              break
            end
            names[#names + 1] = name
          end
          local index = 0
          local function next_entry(copy_err)
            if copy_err then
              callback(copy_err)
              return
            end
            index = index + 1
            local name = names[index]
            if name then
              copy_entry(src .. "/" .. name, dst .. "/" .. name, next_entry)
            else
              uv.fs_chmod(dst, stat.mode % 4096, callback)
            end
          end
          next_entry()
        end)
      end)
    elseif stat.type == "file" then
      uv.fs_copyfile(src, dst, { excl = true }, callback)
    else
      callback("Unsupported source type: " .. stat.type)
    end
  end)
end

local function move_entry(src, dst, callback)
  uv.fs_lstat(src, function(err, stat)
    if err or not stat then
      callback(err or ("Cannot stat source: " .. src))
      return
    end
    if stat.type == "directory" then
      uv.fs_lstat(dst, function(dst_err, existing)
        if existing then
          callback("Destination already exists: " .. dst)
        elseif dst_err and not dst_err:match("^ENOENT") then
          callback(dst_err)
        else
          uv.fs_rename(src, dst, callback)
        end
      end)
      return
    end
    local function unlink_source(copy_err)
      if copy_err then
        callback(copy_err)
      else
        uv.fs_unlink(src, callback)
      end
    end
    if stat.type == "link" then
      copy_entry(src, dst, unlink_source)
    else
      -- A destination check followed by rename can overwrite a concurrent writer's file.
      uv.fs_link(src, dst, function(link_err)
        if link_err and link_err:match("^EXDEV") then
          copy_entry(src, dst, unlink_source)
        else
          unlink_source(link_err)
        end
      end)
    end
  end)
end

local function run(operation, src, dst, callback)
  vim.schedule(function()
    local ok, err = pcall(vim.fn.mkdir, vim.fn.fnamemodify(dst, ":h"), "p")
    if not ok then
      callback(tostring(err))
      return
    end
    operation(src, dst, vim.schedule_wrap(callback))
  end)
end

---@param src string
---@param dst string
---@param callback fun(err?: string)
function M.copy(src, dst, callback)
  run(copy_entry, src, dst, callback)
end

---@param src string
---@param dst string
---@param callback fun(err?: string)
function M.move(src, dst, callback)
  run(move_entry, src, dst, callback)
end

return M
