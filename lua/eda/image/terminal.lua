---Terminal plumbing for image rendering: capability detection, raw output with
---tmux passthrough, screen offsets, and cell geometry.
local M = {}

---Output sink; overridable so tests can capture the exact byte stream.
---@type fun(data: string)?
M.writer = nil

local function raw_write(data)
  if vim.api.nvim_ui_send then
    vim.api.nvim_ui_send(data)
  else
    io.write(data)
    io.flush()
  end
end

local tmux_cache ---@type boolean?

---True when Neovim's output really goes through a tmux pane. `$TMUX` alone is not
---enough: a terminal app launched from a tmux shell inherits the variable while
---drawing straight to its own screen.
---@return boolean
function M.is_tmux()
  if tmux_cache ~= nil then
    return tmux_cache
  end
  if vim.env.TMUX == nil then
    tmux_cache = false
    return false
  end
  -- Without a UI there is no terminal to tunnel through; unit and E2E children
  -- inherit $TMUX from the developer's shell and must not touch that session.
  if #vim.api.nvim_list_uis() == 0 then
    return false
  end
  tmux_cache = true
  pcall(function()
    local ffi = require("ffi")
    pcall(ffi.cdef, "char *ttyname(int);")
    local name = ffi.C.ttyname(1)
    if name == nil or not vim.env.TMUX_PANE then
      return
    end
    local own_tty = ffi.string(name)
    local pane_tty =
      vim.trim(vim.fn.system({ "tmux", "display-message", "-p", "-t", vim.env.TMUX_PANE, "#{pane_tty}" }))
    if vim.v.shell_error == 0 and pane_tty ~= "" then
      tmux_cache = own_tty == pane_tty
    end
  end)
  return tmux_cache
end

---@param data string
---@return string
function M.tmux_wrap(data)
  return "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
end

---Write a raw sequence to the outer terminal, tunnelling through tmux when needed.
---@param data string
function M.write(data)
  if M.is_tmux() then
    data = M.tmux_wrap(data)
  end
  (M.writer or raw_write)(data)
end

local passthrough_enabled = false

---Enable tmux passthrough for the current pane once per session.
function M.ensure_passthrough()
  if passthrough_enabled or not M.is_tmux() then
    return
  end
  passthrough_enabled = true
  -- `on` (visible panes only) is enough: images are only drawn while the pane is shown
  pcall(vim.fn.system, { "tmux", "set", "-p", "allow-passthrough", "on" })
end

---@class eda.image.Terminal
---@field supported boolean
---@field name string

---@param name string
---@return string?
local function classify(name)
  name = name:lower()
  for _, known in ipairs({ "kitty", "ghostty", "wezterm" }) do
    if name:find(known, 1, true) then
      return known
    end
  end
  return nil
end

---Terminal kind suggested by environment variables, or nil. Only trustworthy
---outside tmux, where the variables belong to the terminal Neovim runs in.
---@return string?
function M.env_hint()
  if vim.env.KITTY_WINDOW_ID or (vim.env.TERM or ""):find("kitty", 1, true) then
    return "kitty"
  end
  if vim.env.GHOSTTY_RESOURCES_DIR or (vim.env.TERM or ""):find("ghostty", 1, true) then
    return "ghostty"
  end
  if vim.env.TERM_PROGRAM == "WezTerm" or vim.env.WEZTERM_EXECUTABLE then
    return "wezterm"
  end
  return nil
end

local detected ---@type eda.image.Terminal?
local pending ---@type fun(term: eda.image.Terminal)[]?
local detect_timer ---@type uv.uv_timer_t?

M.detect_timeout_ms = 1000

-- Kitty graphics capability query: a 1x1 RGB probe that any implementation must
-- answer with `ESC _ G i=31;OK ESC \`. Unlike XTVERSION it does not depend on the
-- terminal's name, so unknown terminals that speak the protocol are recognized.
local KITTY_QUERY = "\27_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\27\\"

---Detect whether the terminal can display Kitty graphics. The callback may run
---synchronously when the answer is already known.
---@param cb fun(term: eda.image.Terminal)
function M.detect(cb)
  if detected then
    return cb(detected)
  end
  if pending then
    table.insert(pending, cb)
    return
  end
  pending = { cb }

  local function finish(term)
    detected = term
    local todo = pending or {}
    pending = nil
    for _, fn in ipairs(todo) do
      fn(term)
    end
  end

  if #vim.api.nvim_list_uis() == 0 then
    return finish({ supported = false, name = "headless" })
  end

  local hint = M.env_hint()
  -- Outside tmux the environment belongs to this terminal, so a hint settles it;
  -- inside tmux it describes whichever client started the server and only serves
  -- as the fallback when the terminal does not answer.
  if hint and not M.is_tmux() then
    return finish({ supported = true, name = hint })
  end

  local timer = assert(vim.uv.new_timer())
  detect_timer = timer
  local autocmd_id
  local reported_name ---@type string?
  local function done(term)
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    detect_timer = nil
    if autocmd_id then
      pcall(vim.api.nvim_del_autocmd, autocmd_id)
      autocmd_id = nil
    end
    vim.schedule(function()
      finish(term)
    end)
  end

  autocmd_id = vim.api.nvim_create_autocmd("TermResponse", {
    group = vim.api.nvim_create_augroup("eda_image_detect", { clear = true }),
    callback = function(ev)
      local seq = type(ev.data) == "table" and ev.data.sequence or ev.data
      if type(seq) ~= "string" then
        return
      end
      local name = seq:match("P>|(%S+)")
      if name then
        name = name:gsub("%c", "")
        local kind = classify(name)
        if kind then
          done({ supported = true, name = kind })
          return true
        end
        -- Unknown name: the capability query decides
        reported_name = name
        return
      end
      if seq:match("_G[^;]*i=31[^;]*;OK") then
        done({ supported = true, name = reported_name or "kitty-graphics" })
        return true
      end
    end,
  })
  timer:start(
    M.detect_timeout_ms,
    0,
    vim.schedule_wrap(function()
      done({ supported = hint ~= nil, name = hint or reported_name or "unknown" })
    end)
  )
  -- The probes travel through the passthrough, so it must be enabled first
  M.ensure_passthrough()
  M.write("\27[>q" .. KITTY_QUERY)
end

---Parse `tmux display-message` output into a {row, col} screen offset for the pane.
---@param out string
---@return integer[]
function M.parse_tmux_offset(out)
  local top, left, status_pos, client_h, window_h = out:match("(%-?%d+)%s+(%-?%d+)%s+(%a+)%s+(%d+)%s+(%d+)")
  if not top then
    return { 0, 0 }
  end
  -- pane_top is relative to the window area, which excludes a status line placed at the top
  local status_rows = 0
  if status_pos == "top" then
    status_rows = math.max(0, tonumber(client_h) - tonumber(window_h))
  end
  return { math.max(0, tonumber(top) + status_rows), math.max(0, tonumber(left)) }
end

local offset_cache ---@type integer[]?

---Screen offset of the current tmux pane, {0, 0} outside tmux. Cached until the
---next event-loop tick so one preview update issues at most one tmux call.
---@return integer[]
function M.tmux_offset()
  if not M.is_tmux() then
    return { 0, 0 }
  end
  if offset_cache then
    return offset_cache
  end
  local cmd = {
    "tmux",
    "display-message",
    "-p",
    "#{pane_top} #{pane_left} #{status-position} #{client_height} #{window_height}",
  }
  if vim.env.TMUX_PANE then
    table.insert(cmd, 4, vim.env.TMUX_PANE)
    table.insert(cmd, 4, "-t")
  end
  local ok, out = pcall(vim.fn.system, cmd)
  offset_cache = M.parse_tmux_offset(ok and out or "")
  vim.schedule(function()
    offset_cache = nil
  end)
  return offset_cache
end

---@class eda.image.Size
---@field width number
---@field height number

local cell_cache ---@type eda.image.Size?
local autocmds_registered = false

local function ensure_autocmds()
  if autocmds_registered then
    return
  end
  autocmds_registered = true
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("eda_image_terminal", { clear = true }),
    callback = function()
      cell_cache = nil
    end,
  })
end

---Pixel size of one terminal cell. Falls back to a common 9x18 when the terminal
---does not report pixel dimensions.
---@return eda.image.Size
function M.cell_size()
  ensure_autocmds()
  if cell_cache then
    return cell_cache
  end
  local size = { width = 9, height = 18 }
  pcall(function()
    local ffi = require("ffi")
    pcall(
      ffi.cdef,
      [[
      typedef struct { unsigned short row; unsigned short col; unsigned short xpixel; unsigned short ypixel; } eda_winsize;
      int ioctl(int, int, ...);
    ]]
    )
    local TIOCGWINSZ = vim.fn.has("linux") == 1 and 0x5413 or 0x40087468
    ---@type { row: integer, col: integer, xpixel: integer, ypixel: integer }
    local ws = ffi.new("eda_winsize")
    if ffi.C.ioctl(1, TIOCGWINSZ, ws) == 0 and ws.col > 0 and ws.row > 0 and ws.xpixel > 0 and ws.ypixel > 0 then
      size = { width = ws.xpixel / ws.col, height = ws.ypixel / ws.row }
    end
  end)
  cell_cache = size
  return size
end

---Forget every cached probe result and registered autocmd. Test seam.
function M._reset()
  tmux_cache = nil
  offset_cache = nil
  cell_cache = nil
  detected = nil
  pending = nil
  if detect_timer and not detect_timer:is_closing() then
    detect_timer:stop()
    detect_timer:close()
  end
  detect_timer = nil
  passthrough_enabled = false
  autocmds_registered = false
  pcall(vim.api.nvim_del_augroup_by_name, "eda_image_terminal")
  pcall(vim.api.nvim_del_augroup_by_name, "eda_image_detect")
end

---@class eda.image.BorderSize
---@field top integer
---@field left integer

---Cells taken by a float border at the top and left edges.
---@param border any value of `nvim_win_get_config().border`
---@return eda.image.BorderSize
function M.border_size(border)
  if type(border) == "string" then
    if border == "none" or border == "shadow" or border == "" then
      return { top = 0, left = 0 }
    end
    return { top = 1, left = 1 }
  end
  if type(border) == "table" and #border == 8 then
    local function present(edge)
      local ch = type(edge) == "table" and edge[1] or edge
      return ch ~= nil and ch ~= "" and 1 or 0
    end
    return { top = present(border[2]), left = present(border[8]) }
  end
  return { top = 0, left = 0 }
end

---@class eda.image.Fit
---@field width integer cells
---@field height integer cells
---@field axis "width"|"height" the dimension that limits the placement

---Cells needed to show an image inside a window without upscaling. Only the
---binding axis should be sent to the terminal: rounding both axes to whole cells
---distorts the aspect ratio (cells are tall), whereas the terminal derives the
---other axis from the image's real proportions.
---@param image eda.image.Size pixels
---@param cell eda.image.Size pixels per cell
---@param window eda.image.Size cells
---@return eda.image.Fit
function M.fit_cells(image, cell, window)
  local cols = image.width / cell.width
  local rows = image.height / cell.height
  local by_width, by_height = window.width / cols, window.height / rows
  local scale = math.min(1, by_width, by_height)
  local function cells(n, max)
    return math.max(1, math.min(max, math.floor(n * scale + 0.5)))
  end
  return {
    width = cells(cols, window.width),
    height = cells(rows, window.height),
    -- Unscaled images use the width: cells are narrower than tall, so rounding the
    -- column count loses less size than rounding the row count.
    axis = (scale < 1 and by_height < by_width) and "height" or "width",
  }
end

return M
