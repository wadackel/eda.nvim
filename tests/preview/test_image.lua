local Preview = require("eda.preview")
local config = require("eda.config")
local helpers = require("helpers")
local image = require("eda.preview.image")
local terminal = require("eda.image.terminal")
local convert = require("eda.image.convert")
local kitty = require("eda.image.kitty")

local T = MiniTest.new_set()

local function u32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

-- Header-only PNG: enough for dimension parsing, and the NUL bytes exercise the
-- legacy is_binary() rejection that images must bypass.
local FAKE_PNG = "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(400) .. u32(300) .. "\8\6\0\0\0" .. string.rep("\0", 32)

local captured
local saved = {}

local function stub_terminal(opts)
  opts = opts or {}
  saved.writer = terminal.writer
  saved.detect = terminal.detect
  saved.offset = terminal.tmux_offset
  saved.cell_size = terminal.cell_size
  saved.is_tmux = terminal.is_tmux
  captured = {}
  terminal.writer = function(data)
    captured[#captured + 1] = data
  end
  terminal.is_tmux = function()
    return false
  end
  terminal.detect = function(cb)
    if opts.defer_detect then
      saved.pending_detect = cb
    else
      cb({ supported = opts.supported ~= false, name = "stub" })
    end
  end
  terminal.tmux_offset = function()
    return opts.offset or { 0, 0 }
  end
  terminal.cell_size = function()
    return { width = 10, height = 20 }
  end
end

local function restore_terminal()
  terminal.writer = saved.writer
  terminal.detect = saved.detect
  terminal.tmux_offset = saved.offset
  terminal.cell_size = saved.cell_size
  terminal.is_tmux = saved.is_tmux
  if saved.to_png then
    convert.to_png = saved.to_png
    saved.to_png = nil
  end
  saved.pending_detect = nil
  kitty.del(math.huge)
end

local function find(pattern)
  for _, chunk in ipairs(captured) do
    if chunk:find(pattern, 1, true) then
      return chunk
    end
  end
  return nil
end

local function open_filer_split(cfg)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.cmd("topleft vsplit")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, buf)
  vim.api.nvim_win_set_width(winid, math.floor(vim.o.columns * 30 / 100))
  return winid, buf
end

local function cleanup(items)
  for _, item in ipairs(items) do
    if item.win and vim.api.nvim_win_is_valid(item.win) then
      vim.api.nvim_win_close(item.win, true)
    end
    if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
      vim.api.nvim_buf_delete(item.buf, { force = true })
    end
  end
end

local function buf_lines(p)
  if not p.bufnr or not vim.api.nvim_buf_is_valid(p.bufnr) then
    return {}
  end
  return vim.api.nvim_buf_get_lines(p.bufnr, 0, -1, false)
end

local function setup_preview()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.preview.max_file_size = 10
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local png = temp_dir .. "/photo.png"
  helpers.create_file(png, FAKE_PNG)
  local jpg = temp_dir .. "/photo.jpg"
  helpers.create_file(jpg, "\255\216\255\0jpeg")
  local txt = temp_dir .. "/note.txt"
  helpers.create_file(txt, "hello")
  local filer_winid, filer_buf = open_filer_split(cfg)
  p:attach({ winid = filer_winid, kind = "split_left", config = cfg })
  return p, { dir = temp_dir, png = png, jpg = jpg, txt = txt, win = filer_winid, buf = filer_buf }
end

local function teardown_preview(p, env)
  p:close()
  cleanup({ { win = env.win, buf = env.buf }, { buf = p.bufnr } })
  helpers.remove_temp_dir(env.dir)
end

T["is_image"] = MiniTest.new_set()

T["is_image"]["accepts raster extensions case-insensitively"] = function()
  for _, name in ipairs({ "a.png", "a.jpg", "a.JPEG", "a.gif", "a.webp", "a.bmp", "/x/y/Photo.PNG" }) do
    MiniTest.expect.equality(image.is_image(name), true, name)
  end
end

T["is_image"]["rejects non-image paths"] = function()
  for _, name in ipairs({ "a.txt", "a.lua", "README", "a.png.txt", "png", ".png" }) do
    MiniTest.expect.equality(image.is_image(name), false, name)
  end
end

T["Preview"] = MiniTest.new_set({ hooks = { post_case = restore_terminal } })

T["Preview"]["unsupported terminal shows a text description"] = function()
  stub_terminal({ supported = false })
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return p.winid ~= nil and buf_lines(p)[1] == "Image: photo.png"
  end)
  MiniTest.expect.equality(buf_lines(p)[1], "Image: photo.png")
  MiniTest.expect.equality(
    vim.tbl_contains(buf_lines(p), "Terminal does not support the Kitty graphics protocol."),
    true
  )
  MiniTest.expect.equality(#captured, 0)
  teardown_preview(p, env)
end

T["Preview"]["supported terminal transmits and places the image inside the preview border"] = function()
  stub_terminal({ offset = { 1, 96 } })
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return find("a=p") ~= nil
  end)
  MiniTest.expect.equality(find("a=t") ~= nil, true)
  local pos = vim.api.nvim_win_get_position(p.winid)
  local expected_row = pos[1] + 1 + 1 + 1
  local expected_col = pos[2] + 1 + 96 + 1
  local place = find("a=p")
  MiniTest.expect.equality(place:find(string.format("\27[%d;%dH", expected_row, expected_col), 1, true) ~= nil, true)
  -- 400x300 px at 10x20 px cells is 40x15 cells, which fits any reasonable preview window
  local win_w = vim.api.nvim_win_get_width(p.winid)
  if win_w >= 40 then
    MiniTest.expect.equality(place:find("c=40,", 1, true) ~= nil or place:find("c=40\27", 1, true) ~= nil, true)
  end
  MiniTest.expect.equality(buf_lines(p), { "" })
  teardown_preview(p, env)
end

T["Preview"]["switching to a text file frees the image"] = function()
  stub_terminal()
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return find("a=p") ~= nil
  end)
  captured = {}
  p:show(env.txt)
  helpers.wait_for(1000, function()
    return buf_lines(p)[1] == "hello"
  end)
  MiniTest.expect.equality(buf_lines(p), { "hello" })
  local del = find("a=d")
  MiniTest.expect.equality(del ~= nil and del:find("d=I", 1, true) ~= nil, true)
  teardown_preview(p, env)
end

T["Preview"]["close frees the image"] = function()
  stub_terminal()
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return find("a=p") ~= nil
  end)
  captured = {}
  p:close()
  MiniTest.expect.equality(find("d=I") ~= nil, true)
  teardown_preview(p, env)
end

T["Preview"]["reposition re-places the image at the new window position"] = function()
  stub_terminal()
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return find("a=p") ~= nil
  end)
  captured = {}
  p:reposition()
  local place = find("a=p")
  MiniTest.expect.equality(place ~= nil, true)
  MiniTest.expect.equality(find("a=t"), nil)
  teardown_preview(p, env)
end

T["Preview"]["stale detection callback does not place over a newer text preview"] = function()
  stub_terminal({ defer_detect = true })
  local p, env = setup_preview()
  p:show(env.png)
  helpers.wait_for(1000, function()
    return saved.pending_detect ~= nil
  end)
  p:show(env.txt)
  helpers.wait_for(1000, function()
    return buf_lines(p)[1] == "hello"
  end)
  saved.pending_detect({ supported = true, name = "stub" })
  MiniTest.expect.equality(find("a=p"), nil)
  MiniTest.expect.equality(buf_lines(p), { "hello" })
  teardown_preview(p, env)
end

T["Preview"]["non-PNG without ImageMagick shows a hint"] = function()
  stub_terminal()
  saved.to_png = convert.to_png
  convert.to_png = function(_, cb)
    cb("magick not found")
  end
  local p, env = setup_preview()
  p:show(env.jpg)
  helpers.wait_for(1000, function()
    return p.winid ~= nil and buf_lines(p)[1] == "Image: photo.jpg"
  end)
  MiniTest.expect.equality(vim.tbl_contains(buf_lines(p), "magick not found"), true)
  MiniTest.expect.equality(find("a=p"), nil)
  teardown_preview(p, env)
end

return T
