---PNG inspection and on-demand conversion of other raster formats via ImageMagick.
---Adding a format means adding a row to `converters`; anything that ends up as
---PNG on disk flows through the same transmission path.
local M = {}

M.cache_dir = vim.fn.stdpath("cache") .. "/eda/image"
M.cache_limit = 50

-- Bounds the transmitted payload: the preview pane never needs more pixels than this.
local MAX_SIDE = 2048
-- Files this young may still be in use by another Neovim instance; never prune them.
local FRESH_SECONDS = 60
local CONVERT_TIMEOUT_MS = 10000
local PNG_SIGNATURE = "\137PNG\r\n\26\n"

---@class eda.image.Converter
---@field executable string
---@field coder string ImageMagick input coder

---@param coder string
---@return eda.image.Converter
local function magick(coder)
  return { executable = "magick", coder = coder }
end

local converters = {
  jpg = magick("jpeg"),
  jpeg = magick("jpeg"),
  gif = magick("gif"),
  webp = magick("webp"),
  bmp = magick("bmp"),
} ---@type table<string, eda.image.Converter>

-- Bounds ImageMagick itself: a small file can declare a huge canvas, and -resize
-- only runs after the full decode.
local RESOURCE_LIMITS =
  { "-limit", "memory", "256MiB", "-limit", "map", "512MiB", "-limit", "disk", "1GiB", "-limit", "thread", "1" }

---@param path string
---@return string?
local function extension(path)
  local ext = path:match("[^/]%.([%w]+)$")
  return ext and ext:lower() or nil
end

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
function M.supports(path)
  local ext = extension(path)
  return ext == "png" or (ext ~= nil and converters[ext] ~= nil)
end

---@param path string
---@return eda.image.Converter
local function converter_for(path)
  -- PNG has no table row: it only reaches magick for downscaling
  return converters[extension(path) or ""] or magick("png")
end

---@param src string
---@param part string temporary output path
---@return string[] argv
function M.command_for(src, part)
  local converter = converter_for(src)
  local argv = { converter.executable }
  vim.list_extend(argv, RESOURCE_LIMITS)
  -- The input coder is pinned to the validated extension: ImageMagick otherwise
  -- sniffs the format from the bytes, and a renamed PostScript/PDF file would
  -- reach a delegate. `[0]` keeps only the first frame; `png:` forces the encoder.
  vim.list_extend(argv, {
    string.format("%s:%s[0]", converter.coder, src),
    "-resize",
    string.format("%dx%d>", MAX_SIDE, MAX_SIDE),
    "png:" .. part,
  })
  return argv
end

---@param path string
---@param n integer
---@return string?
local function read_head(path, n)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read(n)
  f:close()
  return data
end

---True when the file must go through ImageMagick: any non-PNG format, or a PNG
---larger than the payload bound.
---@param path string
---@return boolean
function M.needs_magick(path)
  if extension(path) ~= "png" then
    return true
  end
  local dims = M.png_size(read_head(path, 24) or "")
  return dims == nil or dims.width > MAX_SIDE or dims.height > MAX_SIDE
end

---Delete the oldest cached PNGs beyond `cache_limit`, skipping recent ones.
function M.prune()
  local entries = {}
  for name, kind in vim.fs.dir(M.cache_dir) do
    if kind == "file" and name:match("%.png$") then
      local path = M.cache_dir .. "/" .. name
      local stat = vim.uv.fs_stat(path)
      if stat then
        entries[#entries + 1] = { path = path, mtime = stat.mtime.sec }
      end
    end
  end
  table.sort(entries, function(a, b)
    return a.mtime < b.mtime
  end)
  local excess = #entries - M.cache_limit
  local now = os.time()
  for _, entry in ipairs(entries) do
    if excess <= 0 then
      break
    end
    if now - entry.mtime > FRESH_SECONDS then
      vim.uv.fs_unlink(entry.path)
      excess = excess - 1
    end
  end
end

---Produce a PNG for `path` that fits the payload bound, converting through
---`magick` into the cache directory when needed. Calls back on the main loop.
---@param path string
---@param cb fun(err: string?, png_path: string?)
function M.to_png(path, cb)
  if not M.needs_magick(path) then
    return cb(nil, path)
  end
  if vim.fn.executable(converter_for(path).executable) ~= 1 then
    if extension(path) == "png" then
      return cb("Image is larger than 2048px on its longest side; install ImageMagick (magick) to downscale it.")
    end
    return cb("Install ImageMagick (magick) to preview this format.")
  end
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return cb("File not found.")
  end
  -- Converted previews may hold sensitive content; keep them private to the user
  vim.fn.mkdir(M.cache_dir, "p")
  vim.fn.setfperm(M.cache_dir, "rwx------")
  local key = vim.fn.sha256(string.format("%s:%d:%d", path, stat.mtime.sec, stat.size))
  local out = M.cache_dir .. "/" .. key .. ".png"
  if vim.uv.fs_stat(out) then
    return cb(nil, out)
  end
  -- Other Neovim instances read this directory; write to a private part file and
  -- rename so a reader never sees a half-written PNG.
  local part = out .. ".part-" .. vim.uv.os_getpid()
  vim.system(M.command_for(path, part), { text = true, timeout = CONVERT_TIMEOUT_MS }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        vim.uv.fs_unlink(part)
        -- vim.system reports its own timeout as SIGTERM with exit code 124
        if res.signal == 15 and res.code == 124 then
          return cb("Conversion timed out.")
        end
        return cb("magick failed: " .. vim.trim(res.stderr or ""))
      end
      vim.fn.setfperm(part, "rw-------")
      vim.uv.fs_rename(part, out)
      M.prune()
      cb(nil, out)
    end)
  end)
end

return M
