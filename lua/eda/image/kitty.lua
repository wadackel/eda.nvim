---Kitty graphics protocol client. The API mirrors Neovim's experimental
---`vim.ui.img` (`set` / `get` / `del`) so it can be swapped out once that lands.
local terminal = require("eda.image.terminal")

local M = {}

local CHUNK_SIZE = 4096

---@class eda.image.PlacementOpts
---@field row integer 1-indexed screen row
---@field col integer 1-indexed screen column
---@field width integer cells
---@field height integer cells

---@class eda.image.Placement
---@field image_id integer
---@field opts eda.image.PlacementOpts
---@field hidden boolean

-- Random base keeps ids from colliding with other clients sharing the terminal.
local next_id = math.random(1000, 900000)
local state = {} ---@type table<integer, eda.image.Placement>

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

---Transmit PNG bytes and display them.
---@param bytes string
---@param opts eda.image.PlacementOpts
---@return integer id
function M.set(bytes, opts)
  local id = next_id
  next_id = next_id + 1
  transmit(id, bytes)
  local entry = { image_id = id, opts = vim.deepcopy(opts), hidden = false }
  state[id] = entry
  place(id, entry)
  return id
end

---Move or resize an existing placement.
---@param id integer
---@param opts table partial eda.image.PlacementOpts
function M.update(id, opts)
  local entry = assert(state[id], "invalid image id: " .. tostring(id))
  unplace(id, entry)
  entry.opts = vim.tbl_extend("force", entry.opts, opts)
  entry.hidden = false
  place(id, entry)
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
    state = {}
    terminal.write(command({ a = "d", d = "A", q = 2 }))
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
function M.hide_all()
  for id, entry in pairs(state) do
    if not entry.hidden then
      entry.hidden = true
      unplace(id, entry)
    end
  end
end

---Re-display placements removed by `hide_all`.
function M.show_all()
  for id, entry in pairs(state) do
    if entry.hidden then
      entry.hidden = false
      place(id, entry)
    end
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("eda_image_kitty", { clear = true }),
  callback = function()
    M.del(math.huge)
  end,
})

return M
