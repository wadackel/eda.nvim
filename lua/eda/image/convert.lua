---PNG inspection and on-demand conversion of other raster formats via ImageMagick.
local M = {}

local PNG_SIGNATURE = "\137PNG\r\n\26\n"

---@param bytes string
---@return eda.image.Size?
function M.png_size(bytes)
  if #bytes < 24 or bytes:sub(1, 8) ~= PNG_SIGNATURE or bytes:sub(13, 16) ~= "IHDR" then
    return nil
  end
  local function u32(offset)
    local a, b, c, d = bytes:byte(offset, offset + 3)
    return a * 16777216 + b * 65536 + c * 256 + d
  end
  return { width = u32(17), height = u32(21) }
end

---@param path string
---@return boolean
function M.needs_conversion(path)
  return path:lower():match("%.png$") == nil
end

---Produce a PNG for `path`, converting through `magick` into the cache directory
---when the source is another format. Calls back on the main loop.
---@param path string
---@param cb fun(err: string?, png_path: string?)
function M.to_png(path, cb)
  if not M.needs_conversion(path) then
    return cb(nil, path)
  end
  if vim.fn.executable("magick") ~= 1 then
    return cb("Install ImageMagick (magick) to preview this format.")
  end
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return cb("File not found.")
  end
  local dir = vim.fn.stdpath("cache") .. "/eda/image"
  vim.fn.mkdir(dir, "p")
  local key = vim.fn.sha256(string.format("%s:%d:%d", path, stat.mtime.sec, stat.size))
  local out = dir .. "/" .. key .. ".png"
  if vim.uv.fs_stat(out) then
    return cb(nil, out)
  end
  -- `[0]` keeps only the first frame of animated formats; `png:` forces the encoder
  vim.system({ "magick", path .. "[0]", "png:" .. out }, { text = true }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        cb("magick failed: " .. vim.trim(res.stderr or ""))
      else
        cb(nil, out)
      end
    end)
  end)
end

return M
