local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")
local Parser = require("eda.buffer.parser")
local Diff = require("eda.tree.diff")

local T = MiniTest.new_set()

---Paint a root whose children are the given entries, then return the pieces a
---`:w` works from.
---@param entries { name: string, type?: string, children?: { name: string }[] }[]
local function paint(entries)
  local store = Store.new()
  local root = store:set_root("/project")
  store:get(root).children_state = "loaded"
  for _, entry in ipairs(entries) do
    local id = store:add({
      name = entry.name,
      path = "/project/" .. entry.name,
      type = entry.type or "file",
      parent_id = root,
      open = entry.children ~= nil,
    })
    if entry.children then
      store:get(id).children_state = "loaded"
      for _, child in ipairs(entry.children) do
        store:add({
          name = child.name,
          path = "/project/" .. entry.name .. "/" .. child.name,
          type = "file",
          parent_id = id,
        })
      end
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(bufnr, 2)
  painter:paint(Flatten.flatten(store, root))
  return bufnr, store, painter
end

local function operations(bufnr, store, painter)
  local snapshot = painter:get_snapshot()
  local parsed = Parser.parse_lines(bufnr, painter.ns_ids, 2, "/project", painter.ns_header, snapshot)
  return Diff.compute(parsed, snapshot, store)
end

local function lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Retype one line in place. nvim_buf_set_lines would invalidate the node extmark,
---which is not what a user editing the name does.
local function retype(bufnr, lnum, text)
  local old = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  vim.api.nvim_buf_set_text(bufnr, lnum - 1, 0, lnum - 1, #old, { text })
end

T["a name starting with a space survives an untouched save"] = function()
  local bufnr, store, painter = paint({ { name = " leading.txt" } })
  MiniTest.expect.equality(#operations(bufnr, store, painter), 0)
  -- The rendered line must not start with whitespace, or the parser reads it as indent.
  MiniTest.expect.equality(lines(bufnr)[1]:match("^%s") == nil, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a name of only whitespace survives an untouched save"] = function()
  local bufnr, store, painter = paint({ { name = "  " } })
  MiniTest.expect.equality(#operations(bufnr, store, painter), 0)
  MiniTest.expect.equality(lines(bufnr)[1] ~= "", true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a name containing a newline renders instead of throwing"] = function()
  local bufnr, store, painter = paint({ { name = "a\nb.txt" } })
  MiniTest.expect.equality(#lines(bufnr), 1)
  MiniTest.expect.equality(#operations(bufnr, store, painter), 0)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a leading-space name two levels deep is not reparented"] = function()
  local bufnr, store, painter = paint({ { name = "dir", type = "directory", children = { { name = "  two.txt" } } } })
  MiniTest.expect.equality(#operations(bufnr, store, painter), 0)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["editing an unrepresentable name is rejected rather than applied"] = function()
  local bufnr, store, painter = paint({ { name = " leading.txt" } })
  retype(bufnr, 1, "renamed.txt")

  local ops = operations(bufnr, store, painter)
  MiniTest.expect.equality(#ops, 1)
  local result = Diff.validate(ops, store)
  MiniTest.expect.equality(result.valid, false)
  MiniTest.expect.equality(#result.errors, 1)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["deleting an unrepresentable line still yields a delete"] = function()
  local bufnr, store, painter = paint({ { name = " leading.txt" }, { name = "keep.txt" } })
  local removed = nil
  for i, line in ipairs(lines(bufnr)) do
    if line ~= "keep.txt" then
      removed = i
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, removed - 1, removed, false, {})

  local ops = operations(bufnr, store, painter)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "delete")
  MiniTest.expect.equality(ops[1].path, "/project/ leading.txt")
  MiniTest.expect.equality(Diff.validate(ops, store).valid, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["renaming a directory moves its unrepresentable child along"] = function()
  local bufnr, store, painter = paint({ { name = "dir", type = "directory", children = { { name = " inner.txt" } } } })
  retype(bufnr, 1, "renamed/")

  local ops = operations(bufnr, store, painter)
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(ops[1].type, "move")
  MiniTest.expect.equality(ops[1].src, "/project/dir")
  MiniTest.expect.equality(ops[1].dst, "/project/renamed")
  MiniTest.expect.equality(Diff.validate(ops, store).valid, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
