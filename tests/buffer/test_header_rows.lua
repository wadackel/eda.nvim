local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")
local Parser = require("eda.buffer.parser")
local Diff = require("eda.tree.diff")

local T = MiniTest.new_set()

---Paint three root files under a header, and return what a `:w` works from.
---@param header table|false
---@param opts? { filter_active?: boolean }
local function paint(header, opts)
  local store = Store.new()
  local root = store:set_root("/project")
  for _, name in ipairs({ "a.txt", "b.txt", "c.txt" }) do
    store:add({ name = name, path = "/project/" .. name, type = "file", parent_id = root })
  end
  store:get(root).children_state = "loaded"

  local bufnr = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(bufnr, 2)
  painter:paint(Flatten.flatten(store, root), nil, {
    root_path = "/project",
    header = header,
    filter_active = opts and opts.filter_active or false,
  })
  return bufnr, store, painter
end

local function operations(bufnr, store, painter)
  local snapshot = painter:get_snapshot()
  local parsed = Parser.parse_lines(bufnr, painter.ns_ids, 2, "/project", painter.ns_header, snapshot)
  return Diff.compute(parsed, snapshot, store)
end

local function summarize(ops)
  local out = {}
  for _, op in ipairs(ops) do
    out[#out + 1] = op.type .. " " .. (op.src or op.path)
  end
  table.sort(out)
  return out
end

local function edit(bufnr, cmd)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent! " .. cmd)
  end)
end

local FULL_HEADER = { format = "short", divider = true }

T["deleting the header row does not delete an entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "1delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["deleting the divider row does not delete an entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "2delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["deleting both header rows does not delete an entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "1,2delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["deleting up to the first entry deletes only that entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  -- `dgg` with the cursor on a.txt: the header rows go with it.
  edit(bufnr, "1,3delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), { "delete /project/a.txt" })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["clearing the buffer deletes every entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "%delete _")
  MiniTest.expect.equality(
    summarize(operations(bufnr, store, painter)),
    { "delete /project/a.txt", "delete /project/b.txt", "delete /project/c.txt" }
  )
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["editing the header text is not a filesystem change"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "1s/./X/")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a line typed above the first entry is still a create"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { "new.txt" })
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), { "create /project/new.txt" })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["the filter label does not mask the first entry"] = function()
  local bufnr, store, painter = paint(FULL_HEADER, { filter_active = true })
  edit(bufnr, "1delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a single-row header behaves the same"] = function()
  local bufnr, store, painter = paint({ format = "short", divider = false })
  MiniTest.expect.equality(painter.header_lines, 1)
  edit(bufnr, "1delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["a headerless buffer parses from the first row"] = function()
  local bufnr, store, painter = paint(false)
  MiniTest.expect.equality(painter.header_lines, 0)
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  edit(bufnr, "1delete _")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), { "delete /project/a.txt" })
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["undoing a header deletion restores the header rows"] = function()
  local bufnr, store, painter = paint(FULL_HEADER)
  edit(bufnr, "1delete _")
  edit(bufnr, "undo")
  MiniTest.expect.equality(summarize(operations(bufnr, store, painter)), {})
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
