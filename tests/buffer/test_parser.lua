local Parser = require("eda.buffer.parser")
local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")

local T = MiniTest.new_set()

local function setup_painted_buffer()
  local store = Store.new()
  local root = store:set_root("/project")
  store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root, open = true })
  local src = store:get_by_path("/project/src")
  src.children_state = "loaded"
  store:add({ name = "init.lua", path = "/project/src/init.lua", type = "file", parent_id = src.id })
  store:add({ name = "README.md", path = "/project/README.md", type = "file", parent_id = root })
  store:get(root).children_state = "loaded"

  local buf = vim.api.nvim_create_buf(false, true)
  local flat_lines = Flatten.flatten(store, root)
  local painter = Painter.new(buf, 2)
  painter:paint(flat_lines)

  return buf, store, painter, flat_lines
end

T["parse_line extracts node_id from extmark"] = function()
  local buf, _, painter = setup_painted_buffer()
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local parsed = Parser.parse_line(buf, ns, 0, 2) -- first line: src/
  MiniTest.expect.equality(parsed.node_id ~= nil, true)
  MiniTest.expect.equality(parsed.is_dir, true)
  MiniTest.expect.equality(parsed.name, "src")
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["parse_line returns nil node_id for line without extmark"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  new_file.lua" })
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local parsed = Parser.parse_line(buf, ns, 0, 2)
  MiniTest.expect.equality(parsed.node_id, nil)
  MiniTest.expect.equality(parsed.name, "new_file.lua")
  MiniTest.expect.equality(parsed.indent, 1)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["parse_line detects directory from trailing slash"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new_dir/" })
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local parsed = Parser.parse_line(buf, ns, 0, 2)
  MiniTest.expect.equality(parsed.is_dir, true)
  MiniTest.expect.equality(parsed.name, "new_dir")
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["parse_lines reconstructs parent paths"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "src/",
    "  init.lua",
    "  util.lua",
    "README.md",
  })
  local ns = vim.api.nvim_create_namespace("eda_test_parse")
  local result = Parser.parse_lines(buf, ns, 2, "/project")
  MiniTest.expect.equality(#result, 4)
  MiniTest.expect.equality(result[1].full_path, "/project/src")
  MiniTest.expect.equality(result[2].full_path, "/project/src/init.lua")
  MiniTest.expect.equality(result[3].full_path, "/project/src/util.lua")
  MiniTest.expect.equality(result[4].full_path, "/project/README.md")
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["parse_line extracts name without icon stripping"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  -- Name that starts with a short prefix followed by space (used to be misidentified as icon)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a file.txt" })
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local parsed = Parser.parse_line(buf, ns, 0, 2)
  MiniTest.expect.equality(parsed.name, "a file.txt")
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["parse_lines skips header lines"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "~/project",
    "src/",
    "  init.lua",
    "README.md",
  })
  local ns = vim.api.nvim_create_namespace("eda_test_parse_header")
  local result = Parser.parse_lines(buf, ns, 2, "/project", 1)
  MiniTest.expect.equality(#result, 3)
  MiniTest.expect.equality(result[1].full_path, "/project/src")
  MiniTest.expect.equality(result[2].full_path, "/project/src/init.lua")
  MiniTest.expect.equality(result[3].full_path, "/project/README.md")
  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
