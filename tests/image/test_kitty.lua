local kitty = require("eda.image.kitty")
local terminal = require("eda.image.terminal")

local T = MiniTest.new_set()

local captured
local original_writer
local original_is_tmux

T["kitty"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      captured = {}
      original_writer = terminal.writer
      original_is_tmux = terminal.is_tmux
      terminal.writer = function(data)
        captured[#captured + 1] = data
      end
      -- The test process may itself run inside tmux; assert on the unwrapped protocol bytes
      terminal.is_tmux = function()
        return false
      end
      kitty.del(math.huge)
    end,
    post_case = function()
      terminal.writer = original_writer
      terminal.is_tmux = original_is_tmux
    end,
  },
})

local function find(pattern)
  for _, chunk in ipairs(captured) do
    if chunk:find(pattern) then
      return chunk
    end
  end
  return nil
end

T["kitty"]["set transmits base64 chunks then places at the given cell"] = function()
  local bytes = string.rep("x", 5000)
  local id = kitty.set(bytes, { row = 3, col = 105, width = 40, height = 20 })
  MiniTest.expect.equality(type(id), "number")

  local encoded = vim.base64.encode(bytes)
  local first = captured[1]
  MiniTest.expect.equality(first:sub(1, 3), "\27_G")
  MiniTest.expect.equality(first:find("a=t", 1, true) ~= nil, true)
  MiniTest.expect.equality(first:find("f=100", 1, true) ~= nil, true)
  MiniTest.expect.equality(first:find("m=1", 1, true) ~= nil, true)
  MiniTest.expect.equality(first:find(encoded:sub(1, 4096), 1, true) ~= nil, true)
  local second = captured[2]
  MiniTest.expect.equality(second:find("m=0", 1, true) ~= nil, true)
  MiniTest.expect.equality(second:find(encoded:sub(4097), 1, true) ~= nil, true)

  local place = captured[3]
  MiniTest.expect.equality(place:sub(1, 2), "\0277")
  MiniTest.expect.equality(place:find("\27[3;105H", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("a=p", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("c=40", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("r=20", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("C=1", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:sub(-2), "\0278")
  MiniTest.expect.equality(#captured, 3)
end

T["kitty"]["placement with only one axis leaves the other to the terminal"] = function()
  kitty.set("png", { row = 1, col = 1, width = 12 })
  local place = captured[#captured]
  MiniTest.expect.equality(place:find("c=12", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("r=", 1, true), nil)
  kitty.set("png", { row = 1, col = 1, height = 7 })
  place = captured[#captured]
  MiniTest.expect.equality(place:find("r=7", 1, true) ~= nil, true)
  MiniTest.expect.equality(place:find("c=", 1, true), nil)
end

T["kitty"]["get returns a copy of the placement opts"] = function()
  local id = kitty.set("png", { row = 1, col = 2, width = 3, height = 4 })
  MiniTest.expect.equality(kitty.get(id), { row = 1, col = 2, width = 3, height = 4 })
  MiniTest.expect.equality(kitty.get(id + 1000), nil)
end

T["kitty"]["update re-places without retransmitting"] = function()
  local id = kitty.set("png", { row = 1, col = 2, width = 3, height = 4 })
  captured = {}
  kitty.update(id, { row = 5, col = 6 })
  MiniTest.expect.equality(#captured, 2)
  MiniTest.expect.equality(captured[1]:find("a=d", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured[1]:find("d=i", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured[2]:find("\27[5;6H", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured[2]:find("c=3", 1, true) ~= nil, true)
  MiniTest.expect.equality(find("a=t"), nil)
  MiniTest.expect.equality(kitty.get(id), { row = 5, col = 6, width = 3, height = 4 })
end

T["kitty"]["del frees the image data and forgets the id"] = function()
  local id = kitty.set("png", { row = 1, col = 1, width = 1, height = 1 })
  captured = {}
  MiniTest.expect.equality(kitty.del(id), true)
  MiniTest.expect.equality(captured[1]:find("a=d", 1, true) ~= nil, true)
  MiniTest.expect.equality(captured[1]:find("d=I", 1, true) ~= nil, true)
  MiniTest.expect.equality(kitty.get(id), nil)
  MiniTest.expect.equality(kitty.del(id), false)
end

T["kitty"]["hide keeps the placement hidden until every reason is released"] = function()
  local id = kitty.set("png", { row = 2, col = 3, width = 4, height = 5 })
  captured = {}
  kitty.hide_all("focus")
  MiniTest.expect.equality(#captured, 1)
  MiniTest.expect.equality(captured[1]:find("d=i", 1, true) ~= nil, true)
  kitty.hide_all(42)
  captured = {}
  kitty.update(id, { row = 7 })
  kitty.show_all("focus")
  MiniTest.expect.equality(find("a=p"), nil)
  kitty.show_all(42)
  MiniTest.expect.equality(#captured, 1)
  MiniTest.expect.equality(captured[1]:find("\27[7;3H", 1, true) ~= nil, true)
  MiniTest.expect.equality(kitty.get(id), { row = 7, col = 3, width = 4, height = 5 })
end

T["kitty"]["update returns false for an unknown id"] = function()
  captured = {}
  MiniTest.expect.equality(kitty.update(123456789, { row = 1 }), false)
  MiniTest.expect.equality(#captured, 0)
end

T["kitty"]["VimLeavePre cleanup is registered on first set, not on require"] = function()
  kitty._reset()
  MiniTest.expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "eda_image_kitty" }), false)
  kitty.set("png", { row = 1, col = 1, width = 1, height = 1 })
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "eda_image_kitty" })
  MiniTest.expect.equality(ok and #autocmds > 0, true)
end

T["kitty"]["del(math.huge) clears everything"] = function()
  local a = kitty.set("png", { row = 1, col = 1, width = 1, height = 1 })
  local b = kitty.set("png", { row = 1, col = 1, width = 1, height = 1 })
  captured = {}
  MiniTest.expect.equality(kitty.del(math.huge), true)
  MiniTest.expect.equality(kitty.get(a), nil)
  MiniTest.expect.equality(kitty.get(b), nil)
  MiniTest.expect.equality(#captured, 1)
  MiniTest.expect.equality(captured[1]:find("a=d", 1, true) ~= nil, true)
  MiniTest.expect.equality(kitty.del(math.huge), false)
end

return T
