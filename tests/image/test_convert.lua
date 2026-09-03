local convert = require("eda.image.convert")
local helpers = require("helpers")

local T = MiniTest.new_set()

local function u32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function png_header(width, height)
  return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(width) .. u32(height) .. "\8\6\0\0\0"
end

T["png_size"] = MiniTest.new_set()

T["png_size"]["reads width and height from IHDR"] = function()
  MiniTest.expect.equality(convert.png_size(png_header(400, 300)), { width = 400, height = 300 })
end

T["png_size"]["returns nil for non-PNG or truncated data"] = function()
  MiniTest.expect.equality(convert.png_size("GIF89a"), nil)
  MiniTest.expect.equality(convert.png_size(png_header(1, 1):sub(1, 20)), nil)
  MiniTest.expect.equality(convert.png_size(""), nil)
end

T["supports"] = MiniTest.new_set()

T["supports"]["accepts png and every converter format case-insensitively"] = function()
  for _, name in ipairs({ "a.png", "a.PNG", "a.jpg", "a.JPEG", "a.gif", "a.webp", "a.bmp", "/x/y/Photo.Png" }) do
    MiniTest.expect.equality(convert.supports(name), true, name)
  end
end

T["supports"]["rejects non-image paths and bare extensions"] = function()
  for _, name in ipairs({ "a.txt", "a.lua", "README", "a.png.txt", "png", ".png", "/dir/.png" }) do
    MiniTest.expect.equality(convert.supports(name), false, name)
  end
end

T["command_for"] = MiniTest.new_set()

T["command_for"]["downscales to 2048px and writes into a pid-suffixed part file"] = function()
  local argv = convert.command_for("/src/photo.jpg", "/cache/abc.png.part-123")
  MiniTest.expect.equality(argv[1], "magick")
  MiniTest.expect.equality(argv[2], "/src/photo.jpg[0]")
  MiniTest.expect.equality(vim.tbl_contains(argv, "-resize"), true)
  MiniTest.expect.equality(vim.tbl_contains(argv, "2048x2048>"), true)
  MiniTest.expect.equality(argv[#argv], "png:/cache/abc.png.part-123")
end

T["needs_magick"] = MiniTest.new_set()

T["needs_magick"]["is false for a small PNG and true for a large one or another format"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/small.png", png_header(2048, 100))
  helpers.create_file(dir .. "/wide.png", png_header(2049, 100))
  helpers.create_file(dir .. "/tall.png", png_header(100, 3000))
  helpers.create_file(dir .. "/photo.jpg", "\255\216\255")
  MiniTest.expect.equality(convert.needs_magick(dir .. "/small.png"), false)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/wide.png"), true)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/tall.png"), true)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/photo.jpg"), true)
  helpers.remove_temp_dir(dir)
end

T["prune"] = MiniTest.new_set()

local function touch(path, age_seconds)
  local now = os.time()
  vim.uv.fs_utime(path, now - age_seconds, now - age_seconds)
end

T["prune"]["keeps the newest cache_limit files and anything younger than a minute"] = function()
  local dir = helpers.create_temp_dir()
  local saved_dir, saved_limit = convert.cache_dir, convert.cache_limit
  convert.cache_dir = dir
  convert.cache_limit = 5
  -- seven old files, oldest first; plus one brand-new file that must survive regardless of count
  for i = 1, 7 do
    local path = string.format("%s/old%d.png", dir, i)
    helpers.create_file(path, "x")
    touch(path, 3600 * (8 - i))
  end
  helpers.create_file(dir .. "/fresh.png", "x")
  helpers.create_file(dir .. "/note.txt", "x")

  convert.prune()

  local remaining = {}
  for name in vim.fs.dir(dir) do
    remaining[name] = true
  end
  MiniTest.expect.equality(remaining["old1.png"], nil)
  MiniTest.expect.equality(remaining["old2.png"], nil)
  MiniTest.expect.equality(remaining["old3.png"], nil)
  MiniTest.expect.equality(remaining["old4.png"], true)
  MiniTest.expect.equality(remaining["old7.png"], true)
  MiniTest.expect.equality(remaining["fresh.png"], true)
  MiniTest.expect.equality(remaining["note.txt"], true)

  convert.cache_dir, convert.cache_limit = saved_dir, saved_limit
  helpers.remove_temp_dir(dir)
end

return T
