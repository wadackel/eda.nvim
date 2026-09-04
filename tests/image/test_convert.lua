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

T["png_size_of"] = MiniTest.new_set()

T["png_size_of"]["reads the dimensions from the file header only"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/a.png", png_header(640, 480) .. string.rep("\0", 100))
  helpers.create_file(dir .. "/photo.jpg", "\255\216\255")
  MiniTest.expect.equality(convert.png_size_of(dir .. "/a.png"), { width = 640, height = 480 })
  MiniTest.expect.equality(convert.png_size_of(dir .. "/photo.jpg"), nil)
  MiniTest.expect.equality(convert.png_size_of(dir .. "/missing.png"), nil)
  helpers.remove_temp_dir(dir)
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

T["command_for"]["downscales to the given bound and writes into a pid-suffixed part file"] = function()
  local argv = convert.command_for("/src/photo.jpg", "/cache/abc.png.part-123", { width = 1024, height = 768 })
  MiniTest.expect.equality(argv[1], "magick")
  MiniTest.expect.equality(vim.tbl_contains(argv, "-resize"), true)
  MiniTest.expect.equality(vim.tbl_contains(argv, "1024x768>"), true)
  MiniTest.expect.equality(argv[#argv], "png:/cache/abc.png.part-123")
end

T["command_for"]["defaults the bound to the payload cap"] = function()
  local argv = convert.command_for("/src/photo.jpg", "/cache/abc.png.part-123")
  MiniTest.expect.equality(vim.tbl_contains(argv, "2048x2048>"), true)
end

T["command_for"]["encodes with a fast PNG compression level"] = function()
  local argv = convert.command_for("/src/photo.jpg", "/o.png.part-1")
  local defines = {}
  for i, arg in ipairs(argv) do
    if arg == "-define" then
      defines[#defines + 1] = argv[i + 1]
    end
  end
  MiniTest.expect.equality(vim.tbl_contains(defines, "png:compression-level=1"), true)
end

T["command_for"]["hints libjpeg to decode at the target size, only for JPEG input"] = function()
  local function jpeg_size_index(argv)
    for i, arg in ipairs(argv) do
      if arg == "jpeg:size=1024x768" then
        return i
      end
    end
    return nil
  end
  local bound = { width = 1024, height = 768 }
  local jpg = convert.command_for("/src/photo.jpg", "/o.png.part-1", bound)
  local at = jpeg_size_index(jpg)
  MiniTest.expect.equality(at ~= nil, true)
  MiniTest.expect.equality(jpg[at - 1], "-define")
  -- the hint only applies to the input that follows it
  MiniTest.expect.equality(at < vim.fn.index(jpg, "jpeg:/src/photo.jpg[0]") + 1, true)
  MiniTest.expect.equality(jpeg_size_index(convert.command_for("/src/big.png", "/o.png.part-1", bound)), nil)
  MiniTest.expect.equality(jpeg_size_index(convert.command_for("/src/w.webp", "/o.png.part-1", bound)), nil)
end

T["command_for"]["pins the input coder to the validated extension"] = function()
  -- ImageMagick sniffs the format from file content; an explicit coder keeps a
  -- renamed PostScript/PDF/MVG file from reaching a delegate
  local function input(argv)
    for i, arg in ipairs(argv) do
      if arg == "-resize" then
        return argv[i - 1]
      end
    end
  end
  MiniTest.expect.equality(input(convert.command_for("/src/photo.jpg", "/o.png.part-1")), "jpeg:/src/photo.jpg[0]")
  MiniTest.expect.equality(input(convert.command_for("/src/a.JPEG", "/o.png.part-1")), "jpeg:/src/a.JPEG[0]")
  MiniTest.expect.equality(input(convert.command_for("/src/anim.gif", "/o.png.part-1")), "gif:/src/anim.gif[0]")
  MiniTest.expect.equality(input(convert.command_for("/src/w.webp", "/o.png.part-1")), "webp:/src/w.webp[0]")
  MiniTest.expect.equality(input(convert.command_for("/src/b.bmp", "/o.png.part-1")), "bmp:/src/b.bmp[0]")
  MiniTest.expect.equality(input(convert.command_for("/src/big.png", "/o.png.part-1")), "png:/src/big.png[0]")
end

T["command_for"]["caps ImageMagick resources so a decompression bomb cannot exhaust memory"] = function()
  local argv = convert.command_for("/src/photo.jpg", "/o.png.part-1")
  local limits = {}
  for i, arg in ipairs(argv) do
    if arg == "-limit" then
      limits[argv[i + 1]] = argv[i + 2]
    end
  end
  MiniTest.expect.equality(limits.memory ~= nil, true)
  MiniTest.expect.equality(limits.map ~= nil, true)
  MiniTest.expect.equality(limits.disk ~= nil, true)
  MiniTest.expect.equality(limits.thread, "1")
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

T["needs_magick"]["compares against the given bound"] = function()
  local dir = helpers.create_temp_dir()
  local bound = { width = 1024, height = 768 }
  helpers.create_file(dir .. "/fits.png", png_header(1024, 768))
  helpers.create_file(dir .. "/wide.png", png_header(1025, 768))
  helpers.create_file(dir .. "/tall.png", png_header(100, 769))
  helpers.create_file(dir .. "/photo.jpg", "\255\216\255")
  MiniTest.expect.equality(convert.needs_magick(dir .. "/fits.png", bound), false)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/wide.png", bound), true)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/tall.png", bound), true)
  MiniTest.expect.equality(convert.needs_magick(dir .. "/photo.jpg", bound), true)
  helpers.remove_temp_dir(dir)
end

T["bound_for"] = MiniTest.new_set()

T["bound_for"]["rounds each axis up to 256 and caps at the payload bound"] = function()
  MiniTest.expect.equality(convert.bound_for({ width = 1000, height = 700 }), { width = 1024, height = 768 })
  MiniTest.expect.equality(convert.bound_for({ width = 1024, height = 768 }), { width = 1024, height = 768 })
  MiniTest.expect.equality(convert.bound_for({ width = 5000, height = 10 }), { width = 2048, height = 256 })
  MiniTest.expect.equality(convert.bound_for({ width = 1, height = 1 }), { width = 256, height = 256 })
  MiniTest.expect.equality(convert.max_side, 2048)
end

T["bound_for"]["accepts a different cap, including none"] = function()
  MiniTest.expect.equality(convert.bound_for({ width = 5000, height = 10 }, 1024), { width = 1024, height = 256 })
  MiniTest.expect.equality(convert.bound_for({ width = 5000, height = 10 }, math.huge), { width = 5120, height = 256 })
end

T["to_png"] = MiniTest.new_set()

T["to_png"]["without magick keeps a PNG within the payload cap even when it exceeds the bound"] = function()
  local dir = helpers.create_temp_dir()
  helpers.create_file(dir .. "/mid.png", png_header(1500, 100))
  helpers.create_file(dir .. "/huge.png", png_header(4000, 100))
  local saved_executable = vim.fn.executable
  vim.fn.executable = function()
    return 0
  end
  local results = {}
  local ok, err = pcall(function()
    for _, name in ipairs({ "mid.png", "huge.png" }) do
      convert.to_png(dir .. "/" .. name, { width = 768, height = 768 }, function(e, png_path)
        results[name] = { e, png_path }
      end)
    end
  end)
  vim.fn.executable = saved_executable
  helpers.remove_temp_dir(dir)
  if not ok then
    error(err, 0)
  end
  MiniTest.expect.equality(results["mid.png"], { nil, dir .. "/mid.png" })
  MiniTest.expect.equality(
    results["huge.png"][1],
    "Image is larger than 2048px on its longest side; install ImageMagick (magick) to downscale it."
  )
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
