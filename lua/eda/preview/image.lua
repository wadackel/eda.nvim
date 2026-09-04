---Image preview: connects the preview pane to the Kitty graphics client.
local terminal = require("eda.image.terminal")
local kitty = require("eda.image.kitty")
local convert = require("eda.image.convert")
local spinner = require("eda.spinner")

local M = {}

---@class eda.image.PreviewEntry
---@field id integer kitty placement id
---@field dims eda.image.Size image pixels

local entries = {} ---@type table<integer, eda.image.PreviewEntry> keyed by bufnr
local loading = {} ---@type table<integer, eda.Spinner> keyed by bufnr
local ns_hl = vim.api.nvim_create_namespace("eda_image_preview_hl")
local autocmds_registered = false

---@param bufnr integer
local function stop_loading(bufnr)
  local handle = loading[bufnr]
  if not handle then
    return
  end
  loading[bufnr] = nil
  handle.stop()
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_hl, 0, -1)
  end
end

---@param path string
---@return boolean
function M.is_image(path)
  return convert.supports(path)
end

---Replace the buffer content with a short description of `path` and `note`.
---@param bufnr integer
---@param path string
---@param note string
function M.describe(bufnr, path, note)
  stop_loading(bufnr)
  local stat = vim.uv.fs_stat(path)
  local lines = { "Image: " .. vim.fn.fnamemodify(path, ":t") }
  if stat then
    lines[#lines + 1] = string.format("Size: %d bytes", stat.size)
  end
  lines[#lines + 1] = ""
  -- magick's stderr spans several lines; a line containing a newline is rejected
  for _, line in ipairs(vim.split(note:gsub("\r", ""), "\n", { plain = true, trimempty = true })) do
    lines[#lines + 1] = line
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

---Describe `path` with an animated loading note. The glyph is inline virtual
---text rather than part of the line, so ticking never rewrites buffer text.
---@param bufnr integer
---@param path string
function M.loading(bufnr, path)
  M.describe(bufnr, path, "Loading...")
  local row = vim.api.nvim_buf_line_count(bufnr) - 1
  local mark ---@type integer?
  local function paint(glyph)
    mark = vim.api.nvim_buf_set_extmark(bufnr, ns_hl, row, 0, {
      id = mark,
      virt_text = { { glyph .. " ", "EdaPreviewSpinner" } },
      virt_text_pos = "inline",
      hl_mode = "combine",
    })
  end
  local handle
  handle = spinner.new(function(glyph)
    if loading[bufnr] ~= handle or not vim.api.nvim_buf_is_valid(bufnr) then
      handle.stop()
      if loading[bufnr] == handle then
        loading[bufnr] = nil
      end
      return
    end
    paint(glyph)
  end)
  loading[bufnr] = handle
  handle.tick()
  handle.start()
end

---Screen placement for an image shown inside `winid`.
---@param winid integer
---@param dims eda.image.Size
---@return eda.image.PlacementOpts
local function geometry(winid, dims)
  local cfg = vim.api.nvim_win_get_config(winid)
  local border = terminal.border_size(cfg.border)
  local pos = vim.api.nvim_win_get_position(winid)
  local offset = terminal.tmux_offset()
  local fit = terminal.fit_cells(dims, terminal.cell_size(), {
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
  })
  return {
    row = math.max(1, pos[1] + border.top + offset[1] + 1),
    col = math.max(1, pos[2] + border.left + offset[2] + 1),
    width = fit.width,
    height = fit.height,
    crop = fit.crop,
  }
end

---Pixels the preview window can show: its cells times the terminal's cell size.
---Only a direct transmission is held to the payload cap.
---@param winid integer
---@param by_path boolean
---@return eda.image.Size
local function pixel_bound(winid, by_path)
  local cell = terminal.cell_size()
  return convert.bound_for({
    width = vim.api.nvim_win_get_width(winid) * cell.width,
    height = vim.api.nvim_win_get_height(winid) * cell.height,
  }, by_path and math.huge or nil)
end

---@param path string
---@return string?
local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

-- Cursor-positioned images are unknown to tmux, so they would linger over other
-- panes; drop them while Neovim is unfocused and bring them back afterwards.
local function ensure_autocmds()
  if autocmds_registered then
    return
  end
  autocmds_registered = true
  local group = vim.api.nvim_create_augroup("eda_image_preview", { clear = true })
  vim.api.nvim_create_autocmd("FocusLost", {
    group = group,
    callback = function()
      kitty.hide_all("focus")
    end,
  })
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      kitty.show_all("focus")
    end,
  })
end

---@class eda.image.RenderOpts
---@field transmission? "auto"|"file"|"direct" see `preview.image.transmission`

---Whether the terminal should read the PNG from disk (`t=f`) instead of receiving
---its bytes over the tty. Writing megabytes through `nvim_ui_send` blocks the TUI
---until the terminal has consumed them, so the path wins whenever it can resolve
---on the terminal's side.
---@param opts eda.image.RenderOpts
---@return boolean
local function transmit_by_path(opts)
  if opts.transmission == "file" then
    return true
  end
  if opts.transmission == "direct" then
    return false
  end
  return not terminal.is_remote()
end

---@param png_path string
---@param by_path boolean
---@return eda.image.ImageSource?
---@return eda.image.Size?
local function load_source(png_path, by_path)
  if by_path then
    local dims = convert.png_size_of(png_path)
    return dims and { filename = png_path }, dims
  end
  local bytes = read_file(png_path)
  local dims = bytes and convert.png_size(bytes)
  return dims and { data = bytes }, dims
end

---Render `path` into the preview window showing `bufnr`. `is_current` is re-checked
---after every asynchronous step so a slow detection or conversion never paints over
---a newer target.
---@param bufnr integer
---@param winid integer
---@param path string
---@param is_current fun(): boolean
---@param opts? eda.image.RenderOpts
function M.render(bufnr, winid, path, is_current, opts)
  ensure_autocmds()
  local by_path = transmit_by_path(opts or {})
  local function alive()
    return is_current() and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_win_is_valid(winid)
  end
  terminal.detect(function(term)
    if not alive() then
      return
    end
    if not term.supported then
      M.describe(bufnr, path, "Terminal does not support the Kitty graphics protocol.")
      return
    end
    -- Measured after the probe: the window may have been resized while it waited
    convert.to_png(path, pixel_bound(winid, by_path), function(err, png_path)
      if not alive() then
        return
      end
      if err or not png_path then
        M.describe(bufnr, path, err or "Conversion failed.")
        return
      end
      local source, dims = load_source(png_path, by_path)
      if not source or not dims then
        M.describe(bufnr, path, "Could not read PNG header.")
        return
      end
      terminal.ensure_passthrough()
      M.detach(bufnr)
      -- The loading note would stay visible wherever the image does not cover the window
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
      entries[bufnr] = { id = kitty.set(source, geometry(winid, dims)), dims = dims }
    end)
  end)
end

---Free the image shown for `bufnr`, if any.
---@param bufnr integer
function M.detach(bufnr)
  stop_loading(bufnr)
  local entry = entries[bufnr]
  if entry then
    entries[bufnr] = nil
    kitty.del(entry.id)
  end
end

---Re-place the image after the preview window moved or resized.
---@param bufnr integer
---@param winid integer
function M.reposition(bufnr, winid)
  local entry = entries[bufnr]
  if not entry or not vim.api.nvim_win_is_valid(winid) then
    return
  end
  if not kitty.update(entry.id, geometry(winid, entry.dims)) then
    entries[bufnr] = nil
  end
end

---Hide every image while `winid` (a dialog drawn over the preview) is open and
---bring them back when it closes, whichever code path closes it.
---@param winid integer
function M.hide_for_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  -- Nothing to hide unless an image is shown or one is being rendered; a render in
  -- flight has already registered the autocmds, so this also keeps a disabled or
  -- unused image preview from creating any augroup.
  if next(entries) == nil and not autocmds_registered then
    return
  end
  ensure_autocmds()
  kitty.hide_all(winid)
  vim.api.nvim_create_autocmd("WinClosed", {
    group = "eda_image_preview",
    pattern = tostring(winid),
    once = true,
    callback = function()
      kitty.show_all(winid)
    end,
  })
end

---Forget every tracked placement, loading spinner, and registered autocmd. Test seam.
function M._reset()
  for bufnr in pairs(loading) do
    stop_loading(bufnr)
  end
  entries = {}
  autocmds_registered = false
  pcall(vim.api.nvim_del_augroup_by_name, "eda_image_preview")
end

---@param bufnr integer
---@return boolean
function M._is_loading(bufnr)
  return loading[bufnr] ~= nil
end

---Advance the loading spinner of `bufnr` by one frame. Test seam.
---@param bufnr integer
function M._tick_loading(bufnr)
  local handle = loading[bufnr]
  if handle then
    handle.tick()
  end
end

return M
