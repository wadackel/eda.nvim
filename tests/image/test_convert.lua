local convert = require("eda.image.convert")

local T = MiniTest.new_set()

local function png_header(width, height)
  local function u32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
  end
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

T["needs_conversion"] = MiniTest.new_set()

T["needs_conversion"]["is false for png and true for other formats"] = function()
  MiniTest.expect.equality(convert.needs_conversion("/a/b.png"), false)
  MiniTest.expect.equality(convert.needs_conversion("/a/b.PNG"), false)
  MiniTest.expect.equality(convert.needs_conversion("/a/b.jpg"), true)
  MiniTest.expect.equality(convert.needs_conversion("/a/b.webp"), true)
end

return T
