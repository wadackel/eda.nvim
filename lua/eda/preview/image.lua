---Image preview: connects the preview pane to the Kitty graphics client.
local terminal = require("eda.image.terminal")
local kitty = require("eda.image.kitty")
local convert = require("eda.image.convert")

local M = {}

---@class eda.image.PreviewEntry
---@field id integer kitty placement id
---@field dims eda.image.Size image pixels

local entries = {} ---@type table<integer, eda.image.PreviewEntry> keyed by bufnr
local autocmds_registered = false

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
  local stat = vim.uv.fs_stat(path)
  local lines = { "Image: " .. vim.fn.fnamemodify(path, ":t") }
  if stat then
    lines[#lines + 1] = string.format("Size: %d bytes", stat.size)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = note
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
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
  local cells = terminal.fit_cells(dims, terminal.cell_size(), {
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
  })
  return {
    row = pos[1] + border.top + offset[1] + 1,
    col = pos[2] + border.left + offset[2] + 1,
    width = cells.width,
    height = cells.height,
  }
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

---Render `path` into the preview window showing `bufnr`. `is_current` is re-checked
---after every asynchronous step so a slow detection or conversion never paints over
---a newer target.
---@param bufnr integer
---@param winid integer
---@param path string
---@param is_current fun(): boolean
function M.render(bufnr, winid, path, is_current)
  ensure_autocmds()
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
    convert.to_png(path, function(err, png_path)
      if not alive() then
        return
      end
      if err or not png_path then
        M.describe(bufnr, path, err or "Conversion failed.")
        return
      end
      local bytes = read_file(png_path)
      local dims = bytes and convert.png_size(bytes)
      if not bytes or not dims then
        M.describe(bufnr, path, "Could not read PNG header.")
        return
      end
      terminal.ensure_passthrough()
      M.detach(bufnr)
      entries[bufnr] = { id = kitty.set(bytes, geometry(winid, dims)), dims = dims }
    end)
  end)
end

---Free the image shown for `bufnr`, if any.
---@param bufnr integer
function M.detach(bufnr)
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

---Forget every tracked placement and registered autocmd. Test seam.
function M._reset()
  entries = {}
  autocmds_registered = false
  pcall(vim.api.nvim_del_augroup_by_name, "eda_image_preview")
end

return M
