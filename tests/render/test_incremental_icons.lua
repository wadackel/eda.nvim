local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")
local buffers, originals
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      buffers = {}
      originals = {
        set = vim.api.nvim_buf_set_extmark,
        get = vim.api.nvim_buf_get_extmarks,
        provider = vim.api.nvim_set_decoration_provider,
      }
    end,
    post_case = function()
      vim.api.nvim_buf_set_extmark = originals.set
      vim.api.nvim_buf_get_extmarks = originals.get
      vim.api.nvim_set_decoration_provider = originals.provider
      for _, buf in ipairs(buffers) do
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  },
})

local function new_painter()
  local buf = vim.api.nvim_create_buf(false, true)
  buffers[#buffers + 1] = buf
  return Painter.new(buf)
end

local function fixture()
  local store = Store.new()
  local root = store:set_root("/tree")
  local function add(parent, name, dir)
    return store:add({
      name = name,
      path = store:get(parent).path .. "/" .. name,
      parent_id = parent,
      type = dir and "directory" or "file",
      open = dir or false,
      children_state = dir and "loaded" or "unloaded",
    })
  end
  local dir = add(root, "a", true)
  local nested = add(dir, "nested", true)
  for i = 1, 4 do
    add(nested, "child" .. i, false)
  end
  add(dir, "sibling", false)
  local next_dir = add(root, "b", true)
  add(next_dir, "other", false)
  add(root, "no_icon", false)
  add(root, "z", false)
  store:get(root).children_state = "loaded"
  return store, dir, nested
end

local function decorated(store)
  local rows = Flatten.flatten(store, store.root_id)
  local decorations = {}
  for i, row in ipairs(rows) do
    local node = row.node
    decorations[i] = node.name == "no_icon" and {}
      or {
        icon = node.type == "directory" and (node.open and "-" or "+") or "f",
        icon_hl = "Special",
        name_hl = { "EdaMarkedName", "EdaGitModifiedName" },
        suffix = "M",
        suffix_hl = "Special",
      }
  end
  return rows, decorations
end

local function icons(painter)
  local result = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(painter.bufnr, painter.ns_icon, 0, -1, { details = true })) do
    result[#result + 1] = { mark[2], mark[3], mark[4].virt_text, mark[4].right_gravity }
  end
  return result
end

for _, target in ipairs({ "root child", "nested child" }) do
  T["updates only changed icons for a " .. target .. " toggle"] = function()
    local store, dir, nested = fixture()
    local painter, reference = new_painter(), new_painter()
    local rows, decorations = decorated(store)
    painter:paint(rows, decorations)
    local node = store:get(target == "root child" and dir or nested)
    local writes = 0
    vim.api.nvim_buf_set_extmark = function(buf, ns, ...)
      if buf == painter.bufnr and ns == painter.ns_icon then
        writes = writes + 1
      end
      return originals.set(buf, ns, ...)
    end
    for _ = 1, 3 do
      for _, open in ipairs({ false, true }) do
        local old_count = #rows
        node.open = open
        rows, decorations = decorated(store)
        writes = 0
        MiniTest.expect.equality(painter:paint_incremental(rows, decorations, nil, { toggled_node_id = node.id }), true)
        local allowed = open and (#rows - old_count + 2) or 1
        MiniTest.expect.equality(writes <= allowed, true)
        reference:paint(rows, decorations)
        MiniTest.expect.equality(
          vim.api.nvim_buf_get_lines(painter.bufnr, 0, -1, false),
          vim.api.nvim_buf_get_lines(reference.bufnr, 0, -1, false)
        )
        MiniTest.expect.equality(icons(painter), icons(reference))
        MiniTest.expect.equality(painter._decoration_cache, reference._decoration_cache)
        for i, row in ipairs(rows) do
          MiniTest.expect.equality(
            vim.api.nvim_buf_get_extmark_by_id(painter.bufnr, painter.ns_ids, row.node_id, {}),
            { i - 1, 0 }
          )
        end
      end
    end
  end
end

T["redraw skips extmark traversal after paint and after one edit resync"] = function()
  local on_win
  vim.api.nvim_set_decoration_provider = function(ns, opts)
    on_win = opts.on_win
    return originals.provider(ns, opts)
  end
  local store = fixture()
  local painter = new_painter()
  painter:paint(decorated(store))
  local gets = 0
  vim.api.nvim_buf_get_extmarks = function(...)
    gets = gets + 1
    return originals.get(...)
  end
  on_win(nil, nil, painter.bufnr)
  MiniTest.expect.equality(gets, 0)
  vim.api.nvim_buf_set_lines(painter.bufnr, 1, 1, false, { "inserted" })
  on_win(nil, nil, painter.bufnr)
  MiniTest.expect.equality(gets > 0, true)
  gets = 0
  on_win(nil, nil, painter.bufnr)
  MiniTest.expect.equality(gets, 0)
end

T["explicit resync excludes invalidated lines after cached painting"] = function()
  local store = fixture()
  local painter = new_painter()
  local rows, decorations = decorated(store)
  painter:paint(rows, decorations)
  vim.api.nvim_buf_set_lines(painter.bufnr, 2, 3, false, { "replacement" })
  painter:_resync_on_redraw()
  local marks = vim.api.nvim_buf_get_extmarks(painter.bufnr, painter.ns_icon, 0, -1, {})
  for _, mark in ipairs(marks) do
    MiniTest.expect.equality(mark[2] ~= 2, true)
  end
  local shifted = vim.api.nvim_buf_get_extmarks(painter.bufnr, painter.ns_ids, 0, -1, { details = true })
  local valid = {}
  for _, mark in ipairs(shifted) do
    if not mark[4].invalid then
      valid[mark[2]] = true
    end
  end
  for _, mark in ipairs(marks) do
    MiniTest.expect.equality(valid[mark[2]], true)
  end
end

T["rejects incremental painting after unpainted buffer edits"] = function()
  local store, dir = fixture()
  local painter = new_painter()
  painter:paint(decorated(store))
  vim.api.nvim_buf_set_lines(painter.bufnr, 1, 1, false, { "unsaved" })
  local before = vim.api.nvim_buf_get_lines(painter.bufnr, 0, -1, false)
  store:get(dir).open = false
  local rows, decorations = decorated(store)
  MiniTest.expect.equality(painter:paint_incremental(rows, decorations, nil, { toggled_node_id = dir }), false)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(painter.bufnr, 0, -1, false), before)
end

return T
