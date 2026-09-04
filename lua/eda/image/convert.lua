---PNG inspection and on-demand conversion of other raster formats via ImageMagick.
---Adding a format means adding a row to `converters`; anything that ends up as
---PNG on disk flows through the same transmission path.
local M = {}

M.cache_dir = vim.fn.stdpath("cache") .. "/eda/image"
M.cache_limit = 50

-- Hard cap on either axis: bounds the payload of a direct transmission and is the
-- most a PNG may measure to be shown unconverted when magick is unavailable.
M.max_side = 2048
-- Pane-derived bounds round up to this step so small resizes reuse one cache entry
local BOUND_STEP = 256
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

---@return eda.image.Size
local function cap()
  return { width = M.max_side, height = M.max_side }
end

---Pixel bound for a preview area of `size` pixels: each axis rounded up to a
---multiple of `BOUND_STEP` and limited to `max_px`, which defaults to `max_side`.
---That limit only matters when the bytes travel over the tty; a file-path
---transmission passes `math.huge` so a pane wider than it is still filled.
---@param size eda.image.Size
---@param max_px? number
---@return eda.image.Size
function M.bound_for(size, max_px)
  max_px = max_px or M.max_side
  local function quantize(px)
    return math.min(max_px, math.max(BOUND_STEP, math.ceil(px / BOUND_STEP) * BOUND_STEP))
  end
  return { width = quantize(size.width), height = quantize(size.height) }
end

---@param src string
---@param part string temporary output path
---@param bound? eda.image.Size pixels the output must fit; defaults to the cap
---@return string[] argv
function M.command_for(src, part, bound)
  bound = bound or cap()
  local converter = converter_for(src)
  local argv = { converter.executable }
  vim.list_extend(argv, RESOURCE_LIMITS)
  if converter.coder == "jpeg" then
    -- libjpeg can decode straight to a fraction of the full size; without the hint a
    -- 12 MP photo is decoded in full only to be thrown away by -resize
    vim.list_extend(argv, { "-define", string.format("jpeg:size=%dx%d", bound.width, bound.height) })
  end
  -- The input coder is pinned to the validated extension: ImageMagick otherwise
  -- sniffs the format from the bytes, and a renamed PostScript/PDF file would
  -- reach a delegate. `[0]` keeps only the first frame; `png:` forces the encoder.
  -- Default PNG compression spends most of the conversion time for ~15% smaller
  -- files. With file-path transmission the bytes never cross the tty, and for a
  -- direct transmission the conversion time still outweighs the larger payload.
  vim.list_extend(argv, {
    string.format("%s:%s[0]", converter.coder, src),
    "-resize",
    string.format("%dx%d>", bound.width, bound.height),
    "-define",
    "png:compression-level=1",
    "png:" .. part,
  })
  return argv
end

---Dimensions of the PNG at `path`, read from its header alone.
---@param path string
---@return eda.image.Size?
function M.png_size_of(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local head = f:read(24)
  f:close()
  return M.png_size(head or "")
end

---@param dims eda.image.Size?
---@param bound eda.image.Size
---@return boolean
local function exceeds(dims, bound)
  return dims == nil or dims.width > bound.width or dims.height > bound.height
end

---True when the file must go through ImageMagick: any non-PNG format, or a PNG
---larger than `bound` (the cap when omitted).
---@param path string
---@param bound? eda.image.Size
---@return boolean
function M.needs_magick(path, bound)
  if extension(path) ~= "png" then
    return true
  end
  return exceeds(M.png_size_of(path), bound or cap())
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

---Produce a PNG for `path` that fits `bound`, converting through `magick` into
---the cache directory when needed. Calls back on the main loop.
---@param path string
---@param bound? eda.image.Size pixels the result must fit; defaults to the cap
---@param cb fun(err: string?, png_path: string?)
function M.to_png(path, bound, cb)
  bound = bound or cap()
  if not M.needs_magick(path, bound) then
    return cb(nil, path)
  end
  if vim.fn.executable(converter_for(path).executable) ~= 1 then
    if extension(path) == "png" then
      -- Larger than the pane but within the cap: the terminal scales it, so a
      -- missing magick is not a failure here
      if not exceeds(M.png_size_of(path), cap()) then
        return cb(nil, path)
      end
      return cb(
        string.format(
          "Image is larger than %dpx on its longest side; install ImageMagick (magick) to downscale it.",
          M.max_side
        )
      )
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
  local key = vim.fn.sha256(string.format("%s:%d:%d:%dx%d", path, stat.mtime.sec, stat.size, bound.width, bound.height))
  local out = M.cache_dir .. "/" .. key .. ".png"
  if vim.uv.fs_stat(out) then
    return cb(nil, out)
  end
  -- Other Neovim instances read this directory; write to a private part file and
  -- rename so a reader never sees a half-written PNG.
  local part = out .. ".part-" .. vim.uv.os_getpid()
  vim.system(M.command_for(path, part, bound), { text = true, timeout = CONVERT_TIMEOUT_MS }, function(res)
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
