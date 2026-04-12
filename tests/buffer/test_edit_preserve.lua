local Buffer = require("eda.buffer")
local Store = require("eda.tree.store")
local config = require("eda.config")
local edit_preserve = require("eda.buffer.edit_preserve")

local T = MiniTest.new_set()

local test_counter = 0

-- Helper: create a store with a standard directory tree
local function make_store(root_path)
  local store = Store.new()
  local root = store:set_root(root_path)
  store:get(root).children_state = "loaded"

  local dir_a = store:add({ name = "dir_a", path = root_path .. "/dir_a", type = "directory", parent_id = root })
  store:get(dir_a).children_state = "loaded"
  store:get(dir_a).open = true
  store:add({
    name = "file_a.txt",
    path = root_path .. "/dir_a/file_a.txt",
    type = "file",
    parent_id = dir_a,
  })

  local dir_b = store:add({ name = "dir_b", path = root_path .. "/dir_b", type = "directory", parent_id = root })
  store:get(dir_b).children_state = "loaded"
  store:get(dir_b).open = true
  store:add({
    name = "file_b.txt",
    path = root_path .. "/dir_b/file_b.txt",
    type = "file",
    parent_id = dir_b,
  })

  store:add({ name = "root.txt", path = root_path .. "/root.txt", type = "file", parent_id = root })

  return store
end

-- Helper: create a rendered buffer with a unique path to avoid E95
local function make_rendered_buffer(store)
  test_counter = test_counter + 1
  local root_path = store:get(store.root_id).path
  config.setup({ indent = { width = 2 } })
  local buf = Buffer.new(root_path, config.get(), test_counter)
  buf:render(store)
  return buf
end

-- Helper: find a line containing text and return its 0-based row
local function find_line_row(bufnr, text)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:find(text, 1, true) then
      return i - 1
    end
  end
  return nil
end

T["capture"] = MiniTest.new_set()

T["capture"]["detects inserted line as CREATE"] = function()
  local store = make_store("/project/cap1")
  local buf = make_rendered_buffer(store)

  -- Insert a new line after the first entry
  vim.api.nvim_buf_set_lines(buf.bufnr, 1, 1, false, { "new_entry.txt" })
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/cap1", 2)

  MiniTest.expect.equality(#cap.creates, 1)
  MiniTest.expect.equality(cap.creates[1].text, "new_entry.txt")

  buf:destroy()
end

T["capture"]["detects deleted line as DELETE"] = function()
  local store = make_store("/project/cap2")
  local buf = make_rendered_buffer(store)

  local row = find_line_row(buf.bufnr, "root.txt")
  vim.api.nvim_buf_set_lines(buf.bufnr, row, row + 1, false, {})
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/cap2", 2)

  MiniTest.expect.equality(next(cap.deletes) ~= nil, true)

  buf:destroy()
end

T["capture"]["line replace via set_lines produces DELETE and CREATE"] = function()
  -- nvim_buf_set_lines replaces the entire line, which invalidates the extmark.
  -- Without a valid node_id, the diff sees it as DELETE (old) + CREATE (new).
  -- This is correct behavior — MOVE requires the extmark to survive (e.g., ciw).
  local store = make_store("/project/cap3")
  local buf = make_rendered_buffer(store)

  local row = find_line_row(buf.bufnr, "root.txt")
  vim.api.nvim_buf_set_lines(buf.bufnr, row, row + 1, false, { "renamed.txt" })
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/cap3", 2)

  MiniTest.expect.equality(next(cap.deletes) ~= nil, true)
  MiniTest.expect.equality(#cap.creates >= 1, true)

  buf:destroy()
end

T["capture"]["has_edits returns false for empty capture"] = function()
  local cap = { moves = {}, deletes = {}, creates = {}, operations = {} }
  MiniTest.expect.equality(edit_preserve.has_edits(cap), false)
end

T["capture"]["has_edits returns true when creates exist"] = function()
  local cap = { moves = {}, deletes = {}, creates = { { text = "new.txt" } }, operations = {} }
  MiniTest.expect.equality(edit_preserve.has_edits(cap), true)
end

T["replay"] = MiniTest.new_set()

T["replay"]["replays CREATE into freshly rendered buffer"] = function()
  local store = make_store("/project/rep1")
  local buf = make_rendered_buffer(store)

  -- Insert a new line after dir_a/
  vim.api.nvim_buf_set_lines(buf.bufnr, 1, 1, false, { "new_entry.txt" })
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/rep1", 2)
  MiniTest.expect.equality(#cap.creates, 1)

  -- Re-render (simulates what refresh_preserving does)
  buf:render(store)

  -- Replay captured edits
  local replayed = edit_preserve.replay(buf.bufnr, buf.painter, cap, store)
  MiniTest.expect.equality(replayed, true)

  -- Verify new_entry.txt is in the buffer
  MiniTest.expect.equality(find_line_row(buf.bufnr, "new_entry.txt") ~= nil, true)

  buf:destroy()
end

T["replay"]["replays DELETE into freshly rendered buffer"] = function()
  local store = make_store("/project/rep2")
  local buf = make_rendered_buffer(store)

  local row = find_line_row(buf.bufnr, "root.txt")
  vim.api.nvim_buf_set_lines(buf.bufnr, row, row + 1, false, {})
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/rep2", 2)

  buf:render(store)
  edit_preserve.replay(buf.bufnr, buf.painter, cap, store)

  MiniTest.expect.equality(find_line_row(buf.bufnr, "root.txt"), nil)

  buf:destroy()
end

T["replay"]["replays line replacement (DELETE+CREATE) into freshly rendered buffer"] = function()
  -- set_lines produces DELETE + CREATE (extmark invalidated), not MOVE.
  -- After replay, the renamed entry should exist and original should be gone.
  local store = make_store("/project/rep3")
  local buf = make_rendered_buffer(store)

  local row = find_line_row(buf.bufnr, "root.txt")
  vim.api.nvim_buf_set_lines(buf.bufnr, row, row + 1, false, { "renamed.txt" })
  vim.bo[buf.bufnr].modified = true

  local cap = edit_preserve.capture(buf.bufnr, buf.painter, store, "/project/rep3", 2)

  buf:render(store)
  local replayed = edit_preserve.replay(buf.bufnr, buf.painter, cap, store)
  MiniTest.expect.equality(replayed, true)

  -- renamed.txt should exist (CREATE replayed)
  MiniTest.expect.equality(find_line_row(buf.bufnr, "renamed.txt") ~= nil, true)

  buf:destroy()
end

T["replay"]["returns false for empty capture"] = function()
  local store = make_store("/project/rep4")
  local buf = make_rendered_buffer(store)

  local cap = { moves = {}, deletes = {}, creates = {}, operations = {} }
  local replayed = edit_preserve.replay(buf.bufnr, buf.painter, cap, store)
  MiniTest.expect.equality(replayed, false)

  buf:destroy()
end

T["collapse_all keep_open"] = MiniTest.new_set()

T["collapse_all keep_open"]["identifies ancestor dirs of edited paths"] = function()
  local operations = {
    { type = "create", path = "/project/dir_a/new_file.txt", entry_type = "file" },
  }

  -- Build keep_open set (same algorithm as collapse_all in builtin.lua)
  local keep_open = {}
  for _, op in ipairs(operations) do
    for _, p in ipairs({ op.path, op.src }) do
      if p then
        local ancestor = vim.fn.fnamemodify(p, ":h")
        while ancestor and ancestor ~= "" do
          keep_open[ancestor] = true
          local next_a = vim.fn.fnamemodify(ancestor, ":h")
          if next_a == ancestor then
            break
          end
          ancestor = next_a
        end
      end
    end
  end

  MiniTest.expect.equality(keep_open["/project/dir_a"], true)
  MiniTest.expect.equality(keep_open["/project"], true)
  MiniTest.expect.equality(keep_open["/project/dir_b"], nil)
end

T["collapse_all keep_open"]["skips collapsing dirs with edits"] = function()
  local store = make_store("/project/keep1")

  local operations = {
    { type = "create", path = "/project/keep1/dir_a/new_file.txt", entry_type = "file" },
  }

  local keep_open = {}
  for _, op in ipairs(operations) do
    for _, p in ipairs({ op.path, op.src }) do
      if p then
        local ancestor = vim.fn.fnamemodify(p, ":h")
        while ancestor and ancestor ~= "" do
          keep_open[ancestor] = true
          local next_a = vim.fn.fnamemodify(ancestor, ":h")
          if next_a == ancestor then
            break
          end
          ancestor = next_a
        end
      end
    end
  end

  local Node = require("eda.tree.node")
  for _, node in pairs(store.nodes) do
    if Node.is_dir(node) and node.id ~= store.root_id then
      if not keep_open[node.path] then
        node.open = false
      end
    end
  end

  local dir_a = store:get_by_path("/project/keep1/dir_a")
  MiniTest.expect.equality(dir_a.open, true)

  local dir_b = store:get_by_path("/project/keep1/dir_b")
  MiniTest.expect.equality(dir_b.open, false)
end

return T
