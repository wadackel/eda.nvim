local FullName = require("eda.full_name")

local T = MiniTest.new_set()

---@param overrides? table
---@return eda.FlatLine
local function make_flat_line(overrides)
  local defaults = {
    node_id = 1,
    depth = 0,
    node = { name = "file.txt", type = "file" },
  }
  if overrides then
    for k, v in pairs(overrides) do
      defaults[k] = v
    end
  end
  return defaults
end

---@param overrides? table
---@return table
local function make_entry(overrides)
  local defaults = {
    icon_text = nil,
    icon_hl = "EdaFileName",
    name_hl = "EdaFileName",
    suffix = nil,
    suffix_hl = "",
    link_suffix = nil,
    link_suffix_hl = nil,
  }
  if overrides then
    for k, v in pairs(overrides) do
      defaults[k] = v
    end
  end
  return defaults
end

T["compute_display_width"] = MiniTest.new_set()

T["compute_display_width"]["ascii filename only"] = function()
  local fl = make_flat_line({ depth = 2, node = { name = "init.lua", type = "file" } })
  local entry = make_entry()
  -- indent: 2*2=4, icon: 0, name: 8 ("init.lua")
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 12)
end

T["compute_display_width"]["with icon"] = function()
  local fl = make_flat_line({ depth = 1, node = { name = "test.js", type = "file" } })
  local icon_text = "X "
  local entry = make_entry({ icon_text = icon_text })
  -- indent: 1*2=2, icon: nvim_strwidth("X ") = 2, name: 7
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 2 + vim.api.nvim_strwidth(icon_text) + 7)
end

T["compute_display_width"]["with suffix"] = function()
  local fl = make_flat_line({ depth = 0, node = { name = "file.txt", type = "file" } })
  local entry = make_entry({ suffix = "~", suffix_hl = "EdaGitModified" })
  -- indent: 0, icon: 0, name: 8, suffix: 1 ("~")
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 9)
end

T["compute_display_width"]["with link suffix"] = function()
  local fl = make_flat_line({ depth = 0, node = { name = "link", type = "link" } })
  local entry = make_entry({ link_suffix = "-> /target", link_suffix_hl = "EdaSymlinkTarget" })
  -- indent: 0, icon: 0, name: 4, link_suffix: 10 ("-> /target")
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 14)
end

T["compute_display_width"]["both suffixes"] = function()
  local fl = make_flat_line({ depth = 1, node = { name = "link", type = "link" } })
  local entry = make_entry({
    link_suffix = "-> /target",
    link_suffix_hl = "EdaSymlinkTarget",
    suffix = "+",
    suffix_hl = "EdaGitAdded",
  })
  -- indent: 2, icon: 0, name: 4, link_suffix: 10, suffix: 1
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 17)
end

T["compute_display_width"]["directory node adds trailing slash"] = function()
  local fl = make_flat_line({ depth = 0, node = { name = "src", type = "directory" } })
  local entry = make_entry()
  -- indent: 0, icon: 0, name: 4 ("src/")
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 4)
end

T["compute_display_width"]["cjk filename double width"] = function()
  local fl = make_flat_line({ depth = 0, node = { name = "\xe3\x83\x86\xe3\x82\xb9\xe3\x83\x88", type = "file" } }) -- "テスト" = 3 CJK chars = 6 display cols
  local entry = make_entry()
  -- indent: 0, icon: 0, name: 6
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 6)
end

T["compute_display_width"]["no icon sets zero width"] = function()
  local fl = make_flat_line({ depth = 3, node = { name = "a.txt", type = "file" } })
  local entry = make_entry({ icon_text = nil })
  -- indent: 6, icon: 0, name: 5
  local width = FullName.compute_display_width(fl, entry, 2)
  MiniTest.expect.equality(width, 11)
end

return T
