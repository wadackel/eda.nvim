---Kitty graphics protocol client. The API mirrors Neovim's experimental
---`vim.ui.img` (`set` / `get` / `del`) so it can be swapped out once that lands.
local terminal = require("eda.image.terminal")

local M = {}

local CHUNK_SIZE = 4096

---@class eda.image.PlacementOpts
---@field row integer 1-indexed screen row
---@field col integer 1-indexed screen column
---@field width? integer cells; when only one of width/height is given the terminal keeps the aspect ratio
---@field height? integer cells

---@class eda.image.Placement
---@field image_id integer
---@field opts eda.image.PlacementOpts

-- The pid keeps ids from colliding with other Neovim instances sharing the
-- terminal; math.random alone is seeded identically in every LuaJIT process.
local next_id = 1000 + (vim.uv.os_getpid() * 977) % 900000
local state = {} ---@type table<integer, eda.image.Placement>
-- Several callers may hide the image independently (focus loss, a dialog on top);
-- it comes back only when every reason has been released.
local hidden_reasons = {} ---@type table<any, true>
local autocmds_registered = false

local function is_hidden()
  return next(hidden_reasons) ~= nil
end

---@param control table<string, string|integer>
---@param payload string?
---@return string
local function command(control, payload)
  local parts = {}
  for key, value in pairs(control) do
    parts[#parts + 1] = key .. "=" .. tostring(value)
  end
  return "\27_G" .. table.concat(parts, ",") .. (payload and (";" .. payload) or "") .. "\27\\"
end

---@param image_id integer
---@param bytes string PNG data
local function transmit(image_id, bytes)
  local data = vim.base64.encode(bytes)
  local pos = 1
  local first = true
  repeat
    local chunk = data:sub(pos, pos + CHUNK_SIZE - 1)
    pos = pos + CHUNK_SIZE
    local more = pos <= #data and 1 or 0
    local control = first and { a = "t", f = 100, i = image_id, q = 2, m = more } or { m = more }
    terminal.write(command(control, chunk))
    first = false
  until pos > #data
end

---Cursor-positioned placement. Save/move/place/restore go out as one write: tmux
---homes the outer cursor after every passthrough chunk, so a separate cursor move
---would be undone before the placement arrives.
---@param id integer
---@param entry eda.image.Placement
local function place(id, entry)
  local o = entry.opts
  terminal.write(
    "\0277"
      .. string.format("\27[%d;%dH", o.row, o.col)
      .. command({ a = "p", i = entry.image_id, p = id, C = 1, c = o.width, r = o.height, q = 2 })
      .. "\0278"
  )
end

---@param id integer
---@param entry eda.image.Placement
local function unplace(id, entry)
  terminal.write(command({ a = "d", d = "i", i = entry.image_id, p = id, q = 2 }))
end

local function ensure_autocmds()
  if autocmds_registered then
    return
  end
  autocmds_registered = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("eda_image_kitty", { clear = true }),
    callback = function()
      M.del(math.huge)
    end,
  })
end

---Transmit PNG bytes and display them.
---@param bytes string
---@param opts eda.image.PlacementOpts
---@return integer id
function M.set(bytes, opts)
  ensure_autocmds()
  local id = next_id
  next_id = next_id + 1
  transmit(id, bytes)
  local entry = { image_id = id, opts = vim.deepcopy(opts) }
  state[id] = entry
  if not is_hidden() then
    place(id, entry)
  end
  return id
end

---Move or resize an existing placement.
---@param id integer
---@param opts table partial eda.image.PlacementOpts
---@return boolean found
function M.update(id, opts)
  local entry = state[id]
  if not entry then
    return false
  end
  if not is_hidden() then
    unplace(id, entry)
  end
  local merged = vim.tbl_extend("force", entry.opts, opts)
  -- width/height form one unit: a caller that sends a single axis relies on the
  -- terminal deriving the other, so a stale value from the previous call must not survive
  if opts.width ~= nil or opts.height ~= nil then
    merged.width, merged.height = opts.width, opts.height
  end
  entry.opts = merged
  if not is_hidden() then
    place(id, entry)
  end
  return true
end

---@param id integer
---@return eda.image.PlacementOpts?
function M.get(id)
  local entry = state[id]
  return entry and vim.deepcopy(entry.opts) or nil
end

---Delete an image and free its data in the terminal, or everything with `math.huge`.
---@param id integer
---@return boolean found
function M.del(id)
  if id == math.huge then
    if next(state) == nil then
      return false
    end
    -- Delete per image rather than `d=A`: the latter would also wipe images that
    -- other clients sharing this terminal window (tmux panes) have placed.
    local all = state
    state = {}
    for _, entry in pairs(all) do
      terminal.write(command({ a = "d", d = "I", i = entry.image_id, q = 2 }))
    end
    return true
  end
  local entry = state[id]
  if not entry then
    return false
  end
  state[id] = nil
  terminal.write(command({ a = "d", d = "I", i = entry.image_id, q = 2 }))
  return true
end

---Remove every placement from the screen while keeping the image data.
---@param reason any identifies the caller; `show_all` with the same value releases it
function M.hide_all(reason)
  if hidden_reasons[reason] then
    return
  end
  local was_hidden = is_hidden()
  hidden_reasons[reason] = true
  if was_hidden then
    return
  end
  for id, entry in pairs(state) do
    unplace(id, entry)
  end
end

---Release one hide reason; placements return once no reason remains.
---@param reason any
function M.show_all(reason)
  if not hidden_reasons[reason] then
    return
  end
  hidden_reasons[reason] = nil
  if is_hidden() then
    return
  end
  for id, entry in pairs(state) do
    place(id, entry)
  end
end

---Forget all placements, hide reasons, and registered autocmds. Test seam.
function M._reset()
  state = {}
  hidden_reasons = {}
  autocmds_registered = false
  pcall(vim.api.nvim_del_augroup_by_name, "eda_image_kitty")
end

return M
