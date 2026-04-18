local Store = require("eda.tree.store")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")

local T = MiniTest.new_set()

local function build_store()
  local store = Store.new()
  local root = store:set_root("/project")
  local src = store:add({ name = "src", path = "/project/src", type = "directory", parent_id = root, open = true })
  store:add({ name = "init.lua", path = "/project/src/init.lua", type = "file", parent_id = src })
  store:add({ name = "README.md", path = "/project/README.md", type = "file", parent_id = root })

  store:get(root).children_state = "loaded"
  store:get(src).children_state = "loaded"

  return store, root
end

T["paint sets buffer lines"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)
  -- First line: src/ (directory, depth 0)
  MiniTest.expect.equality(lines[1]:find("src/") ~= nil, true)
  -- Second line: init.lua (file, depth 1, indented)
  MiniTest.expect.equality(lines[2]:find("init.lua") ~= nil, true)
  MiniTest.expect.equality(lines[2]:sub(1, 2), "  ") -- 2-space indent
  -- Third line: README.md (file, depth 0)
  MiniTest.expect.equality(lines[3]:find("README.md") ~= nil, true)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint sets node ID extmarks"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  MiniTest.expect.equality(#marks, 3) -- 3 nodes

  -- Extmark IDs should match node IDs
  local mark_ids = {}
  for _, m in ipairs(marks) do
    table.insert(mark_ids, m[1])
  end
  for _, fl in ipairs(flat_lines) do
    local found = vim.tbl_contains(mark_ids, fl.node_id)
    MiniTest.expect.equality(found, true)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint updates snapshot"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  local snapshot = painter:get_snapshot()
  MiniTest.expect.equality(type(snapshot.entries), "table")
  -- Should have entry for each node
  for _, fl in ipairs(flat_lines) do
    local entry = snapshot.entries[fl.node_id]
    MiniTest.expect.equality(entry ~= nil, true)
    MiniTest.expect.equality(entry.path, fl.node.path)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint clears old extmarks on repaint"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Paint twice
  painter:paint(flat_lines)
  painter:paint(flat_lines)

  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  -- Should still have exactly 3 marks (not 6)
  MiniTest.expect.equality(#marks, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint with header prepends 1 line for split mode"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines, nil, {
    root_path = "/Users/test/project",
    header = { format = "short" },
    kind = "split_left",
  })

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 1 header line + 3 file lines = 4
  MiniTest.expect.equality(#lines, 4)
  MiniTest.expect.equality(painter.header_lines, 1)

  -- First line is the header text
  MiniTest.expect.equality(lines[1]:find("project") ~= nil, true)
  -- Second line onwards are file entries
  MiniTest.expect.equality(lines[2]:find("src/") ~= nil, true)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint with header and divider prepends 2 lines for split mode"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines, nil, {
    root_path = "/Users/test/project",
    header = { format = "short", divider = true },
    kind = "split_left",
  })

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- 2 header lines + 3 file lines = 5
  MiniTest.expect.equality(#lines, 5)
  MiniTest.expect.equality(painter.header_lines, 2)

  -- First line is the header text
  MiniTest.expect.equality(lines[1]:find("project") ~= nil, true)
  -- Second line is the divider
  local sep_char = string.char(0xe2, 0x94, 0x80)
  MiniTest.expect.equality(lines[2]:find(sep_char) ~= nil, true)
  -- Third line onwards are file entries
  MiniTest.expect.equality(lines[3]:find("src/") ~= nil, true)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint without header has 0 header_lines"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines, nil, {
    root_path = "/Users/test/project",
    header = false,
    kind = "split_left",
  })

  MiniTest.expect.equality(painter.header_lines, 0)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint skips header for float mode"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines, nil, {
    root_path = "/Users/test/project",
    header = { format = "short" },
    kind = "float",
  })

  MiniTest.expect.equality(painter.header_lines, 0)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_build_line produces indent and name without icon"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- flat_lines[1] is src/ at depth 0
  local line = painter:_build_line(flat_lines[1])
  MiniTest.expect.equality(line, "src/")

  -- flat_lines[2] is init.lua at depth 1
  line = painter:_build_line(flat_lines[2])
  MiniTest.expect.equality(line, "  init.lua")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint populates _decoration_cache with icon data"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  -- Buffer text should NOT contain the icon
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(lines[1], "src/")
  MiniTest.expect.equality(lines[2], "  init.lua")
  MiniTest.expect.equality(lines[3], "README.md")

  -- Decoration cache should have icon data for each node
  local cache_count = 0
  for _, entry in pairs(painter._decoration_cache) do
    cache_count = cache_count + 1
    MiniTest.expect.equality(entry.icon_text, "X ")
  end
  MiniTest.expect.equality(cache_count, #flat_lines)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint write without changes produces no modifications"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  -- Buffer should not be modified after paint
  MiniTest.expect.equality(vim.bo[buf].modified, false)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_decoration_cache populated after paint"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  -- Cache should have entries for each flat_line
  local cache_count = 0
  for _ in pairs(painter._decoration_cache) do
    cache_count = cache_count + 1
  end
  MiniTest.expect.equality(cache_count, #flat_lines)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint populates _decoration_cache with suffix data"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = {}
  end
  -- Add suffix to the first entry (src/)
  decorations[1].suffix = "~"
  decorations[1].suffix_hl = "EdaGitModified"

  painter:paint(flat_lines, decorations)

  -- First node should have suffix in cache
  local first_node_id = flat_lines[1].node_id
  local entry = painter._decoration_cache[first_node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  MiniTest.expect.equality(entry.suffix, "~")
  MiniTest.expect.equality(entry.suffix_hl, "EdaGitModified")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint re-places ns_ids extmarks on repaint with same flat_lines"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)
  painter:paint(flat_lines)

  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  MiniTest.expect.equality(#marks, 3)

  -- All extmark IDs should match node IDs
  local mark_ids = {}
  for _, m in ipairs(marks) do
    mark_ids[m[1]] = true
  end
  for _, fl in ipairs(flat_lines) do
    MiniTest.expect.equality(mark_ids[fl.node_id] ~= nil, true)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint restores ns_ids extmarks after external buffer modification"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Initial paint
  painter:paint(flat_lines)

  -- External modification that invalidates extmarks (simulates the bug scenario)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "replaced", "lines" })

  -- Repaint with same flat_lines should restore all extmarks
  painter:paint(flat_lines)

  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  MiniTest.expect.equality(#marks, #flat_lines)

  -- Verify extmark IDs match node IDs
  local mark_ids = {}
  for _, m in ipairs(marks) do
    mark_ids[m[1]] = true
  end
  for _, fl in ipairs(flat_lines) do
    MiniTest.expect.equality(mark_ids[fl.node_id] ~= nil, true)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_build_header_text"] = MiniTest.new_set()

T["_build_header_text"]["short format uses tilde notation"] = function()
  local result = Painter._build_header_text(vim.fn.expand("~") .. "/project", "short")
  MiniTest.expect.equality(result, "~/project")
end

T["_build_header_text"]["full format returns raw path"] = function()
  local result = Painter._build_header_text("/Users/test/project", "full")
  MiniTest.expect.equality(result, "/Users/test/project")
end

T["_build_header_text"]["minimal format shortens intermediate dirs"] = function()
  local result = Painter._build_header_text(vim.fn.expand("~") .. "/dev/repos/project", "minimal")
  MiniTest.expect.equality(result, "~/d/r/project")
end

T["_build_header_text"]["custom function"] = function()
  local result = Painter._build_header_text("/Users/test/project", function(path)
    return "ROOT: " .. path
  end)
  MiniTest.expect.equality(result, "ROOT: /Users/test/project")
end

T["multiple painters use independent decoration provider namespaces"] = function()
  local buf1 = vim.api.nvim_create_buf(false, true)
  local buf2 = vim.api.nvim_create_buf(false, true)
  local painter1 = Painter.new(buf1)
  local painter2 = Painter.new(buf2)

  -- Each painter must have a unique ns_hl for independent decoration providers
  MiniTest.expect.equality(painter1.ns_hl ~= painter2.ns_hl, true)

  vim.api.nvim_buf_delete(buf1, { force = true })
  vim.api.nvim_buf_delete(buf2, { force = true })
end

T["paint creates icon extmarks in ns_icon namespace"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  local marks = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, { details = true })
  MiniTest.expect.equality(#marks, #flat_lines)

  for _, m in ipairs(marks) do
    local details = m[4]
    MiniTest.expect.equality(details.virt_text, { { "X ", "TestHL" } })
    MiniTest.expect.equality(details.virt_text_pos, "inline")
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint clears old icon extmarks on repaint"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- First paint with icons
  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end
  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  local marks1 = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(#marks1, #flat_lines)

  -- Second paint without decorations
  painter:paint(flat_lines)

  local marks2 = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(#marks2, 0)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint creates icon extmarks only for nodes with icon_text"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Only set icon for directory nodes (first node is src/)
  local decorations = {}
  for i, fl in ipairs(flat_lines) do
    if fl.node.type == "directory" then
      decorations[i] = { icon = "D", icon_hl = "DirHL" }
    else
      decorations[i] = { suffix = "~", suffix_hl = "Comment" }
    end
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  local marks = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, { details = true })
  -- Only 1 directory (src/) in build_store
  MiniTest.expect.equality(#marks, 1)
  MiniTest.expect.equality(marks[1][4].virt_text, { { "D ", "DirHL" } })

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_row_to_fl mapping is built correctly after paint"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  -- With no header, row 0 -> fl 1, row 1 -> fl 2, row 2 -> fl 3
  MiniTest.expect.equality(painter._row_to_fl[0], 1)
  MiniTest.expect.equality(painter._row_to_fl[1], 2)
  MiniTest.expect.equality(painter._row_to_fl[2], 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_row_to_fl mapping accounts for header lines"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines, nil, {
    root_path = "/Users/test/project",
    header = { format = "short" },
    kind = "split_left",
  })

  -- With 1 header line, row 1 -> fl 1, row 2 -> fl 2, row 3 -> fl 3
  MiniTest.expect.equality(painter._row_to_fl[0], nil)
  MiniTest.expect.equality(painter._row_to_fl[1], 1)
  MiniTest.expect.equality(painter._row_to_fl[2], 2)
  MiniTest.expect.equality(painter._row_to_fl[3], 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["resync_highlights places icons at correct rows after line deletion"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  -- Simulate user deleting the second line (init.lua) with dd
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, {})

  painter:resync_highlights()

  -- After deletion, icon extmarks should be at the actual rows of surviving nodes
  local marks = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, { details = true })
  -- Only 2 surviving nodes (src/ at row 0, README.md at row 1)
  MiniTest.expect.equality(#marks, 2)
  MiniTest.expect.equality(marks[1][2], 0) -- src/ icon at row 0
  MiniTest.expect.equality(marks[2][2], 1) -- README.md icon at row 1

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["resync_highlights places icons at correct rows after line insertion"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i = 1, #flat_lines do
    decorations[i] = { icon = "X", icon_hl = "TestHL" }
  end

  painter:paint(flat_lines, decorations, { icon = { separator = " " } })

  -- Simulate user inserting a blank line after the first line (o key)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "" })

  painter:resync_highlights()

  -- After insertion, node extmarks shift down. Icons should follow.
  local marks = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, { details = true })
  MiniTest.expect.equality(#marks, 3) -- all 3 nodes still valid

  -- Row positions: src/ at 0, init.lua shifted to 2, README.md shifted to 3
  local rows = {}
  for _, m in ipairs(marks) do
    table.insert(rows, m[2])
  end
  table.sort(rows)
  MiniTest.expect.equality(rows[1], 0) -- src/ stays at row 0
  MiniTest.expect.equality(rows[2], 2) -- init.lua shifted to row 2
  MiniTest.expect.equality(rows[3], 3) -- README.md shifted to row 3

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["resync_highlights rebuilds _row_to_fl after line insertion"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  -- Insert a blank line after row 0
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "" })

  painter:resync_highlights()

  -- Row 0 -> fl 1 (src/), row 1 is blank (no mapping), row 2 -> fl 2, row 3 -> fl 3
  MiniTest.expect.equality(painter._row_to_fl[0], 1)
  MiniTest.expect.equality(painter._row_to_fl[1], nil) -- blank inserted line
  MiniTest.expect.equality(painter._row_to_fl[2], 2)
  MiniTest.expect.equality(painter._row_to_fl[3], 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["resync_highlights _line_lengths correct after line insertion"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  painter:paint(flat_lines)

  -- Insert a blank line after row 0
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "" })

  painter:resync_highlights()

  -- _line_lengths should reflect actual node line lengths (not blank lines)
  MiniTest.expect.equality(painter._line_lengths[1], #"src/")
  MiniTest.expect.equality(painter._line_lengths[2], #"  init.lua")
  MiniTest.expect.equality(painter._line_lengths[3], #"README.md")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_resync_on_redraw fixes icons after o-style newline insertion"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Paint with decorations so icon extmarks are placed
  local decorations = {}
  for i, fl in ipairs(flat_lines) do
    decorations[i] = { icon = "X", icon_hl = "Normal" }
  end
  painter:paint(flat_lines, decorations)

  -- Verify initial icon positions
  local icons_before = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(icons_before[1][2], 0) -- src/ icon at row 0
  MiniTest.expect.equality(icons_before[2][2], 1) -- init.lua icon at row 1
  MiniTest.expect.equality(icons_before[3][2], 2) -- README.md icon at row 2

  -- Simulate 'o' key: insert newline at end of line 0 (character-level, like Neovim's 'o')
  -- This differs from nvim_buf_set_lines which is line-level insertion
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  local line0 = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  vim.api.nvim_buf_set_text(buf, 0, #line0, 0, #line0, { "", "" })

  -- Check how extmarks behave with character-level newline insertion
  local ns_ids_marks = vim.api.nvim_buf_get_extmarks(buf, painter.ns_ids, 0, -1, {})
  local icons_after_insert = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})

  -- ns_ids (right_gravity=true default): should shift correctly
  -- Row 0: src/ stays, Row 1: new empty, Row 2: init.lua, Row 3: README.md
  MiniTest.expect.equality(ns_ids_marks[1][2], 0) -- src/ stays at row 0
  MiniTest.expect.equality(ns_ids_marks[2][2], 2) -- init.lua shifted to row 2
  MiniTest.expect.equality(ns_ids_marks[3][2], 3) -- README.md shifted to row 3

  -- After resync: icons should match ns_ids positions
  painter:_resync_on_redraw()

  local icons_fixed = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(#icons_fixed, 3)
  MiniTest.expect.equality(icons_fixed[1][2], 0) -- src/ icon at row 0
  MiniTest.expect.equality(icons_fixed[2][2], 2) -- init.lua icon at row 2
  MiniTest.expect.equality(icons_fixed[3][2], 3) -- README.md icon at row 3

  -- _row_to_fl should also be correct
  MiniTest.expect.equality(painter._row_to_fl[0], 1) -- src/
  MiniTest.expect.equality(painter._row_to_fl[1], nil) -- blank line
  MiniTest.expect.equality(painter._row_to_fl[2], 2) -- init.lua
  MiniTest.expect.equality(painter._row_to_fl[3], 3) -- README.md

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_resync_on_redraw repositions misaligned icon extmarks"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i, fl in ipairs(flat_lines) do
    decorations[i] = { icon = "X", icon_hl = "Normal" }
  end
  painter:paint(flat_lines, decorations)

  -- Manually simulate what happens when icon extmarks don't shift with line insertion:
  -- Insert a blank line, then place icons at WRONG positions (simulating right_gravity=false behavior)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 1, 1, false, { "" })

  -- Force icons to be at stale positions (as if they didn't shift)
  vim.api.nvim_buf_clear_namespace(buf, painter.ns_icon, 0, -1)
  local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, fl in ipairs(flat_lines) do
    local entry = painter._decoration_cache[fl.node_id]
    if entry and entry.icon_text then
      -- Place at ORIGINAL row positions (pre-insertion), which are now wrong
      local row = i - 1
      local line = all_lines[row + 1] or ""
      local col = math.min(fl.depth * painter.indent_width, #line)
      vim.api.nvim_buf_set_extmark(buf, painter.ns_icon, row, col, {
        virt_text = { { entry.icon_text, entry.icon_hl } },
        virt_text_pos = "inline",
        right_gravity = false,
      })
    end
  end

  -- Verify icons are at wrong positions
  local icons_wrong = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(icons_wrong[2][2], 1) -- init.lua icon at row 1 (WRONG: blank line)
  MiniTest.expect.equality(icons_wrong[3][2], 2) -- README.md icon at row 2 (WRONG: should be 3)

  -- _resync_on_redraw should detect mismatch and fix icons
  painter:_resync_on_redraw()

  local icons_fixed = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(#icons_fixed, 3)
  MiniTest.expect.equality(icons_fixed[1][2], 0) -- src/ at row 0
  MiniTest.expect.equality(icons_fixed[2][2], 2) -- init.lua at row 2 (correct)
  MiniTest.expect.equality(icons_fixed[3][2], 3) -- README.md at row 3 (correct)

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["_resync_on_redraw skips icon rebuild when positions match"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local decorations = {}
  for i, fl in ipairs(flat_lines) do
    decorations[i] = { icon = "X", icon_hl = "Normal" }
  end
  painter:paint(flat_lines, decorations)

  -- Get icon extmark IDs before resync
  local icons_before = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  local ids_before = {}
  for _, m in ipairs(icons_before) do
    table.insert(ids_before, m[1])
  end

  -- Call resync without any buffer changes: icons should NOT be rebuilt
  painter:_resync_on_redraw()

  -- Same extmark IDs means they were not cleared and re-created
  local icons_after = vim.api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})
  for i, m in ipairs(icons_after) do
    MiniTest.expect.equality(m[1], ids_before[i])
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

-- =============================================
-- resolve_name_hl fallback for transparent name highlight groups
-- =============================================

T["resolve_name_hl falls back to EdaFileName when name_hl group is empty"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Set up an empty highlight group (simulating transparent EdaGit*Name)
  vim.api.nvim_set_hl(0, "TestTransparentName", {})

  -- Apply decoration with empty name_hl to a file node (init.lua, index 2)
  local decorations = {}
  decorations[2] = { suffix = "+", suffix_hl = "EdaGitAddedIcon", name_hl = "TestTransparentName" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- Empty name_hl should fall back to EdaFileName
  MiniTest.expect.equality(entry.name_hl, "EdaFileName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestTransparentName", {})
end

T["resolve_name_hl falls back to EdaDirectoryName when name_hl group is empty for directory"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  vim.api.nvim_set_hl(0, "TestTransparentName", {})

  -- Apply decoration with empty name_hl to a directory node (src/, index 1)
  local decorations = {}
  decorations[1] = { suffix = "+", suffix_hl = "EdaGitAddedIcon", name_hl = "TestTransparentName" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[1].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- Empty name_hl on a directory should fall back to EdaDirectoryName or EdaOpenedDirectoryName
  -- src/ is open, so it should be EdaOpenedDirectoryName
  MiniTest.expect.equality(entry.name_hl, "EdaOpenedDirectoryName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestTransparentName", {})
end

T["resolve_name_hl uses name_hl when group has visual attributes"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Set up a highlight group with fg (simulating user-customized EdaGitAddedName)
  vim.api.nvim_set_hl(0, "TestColoredName", { fg = 0x00FF00 })

  local decorations = {}
  decorations[2] = { suffix = "+", suffix_hl = "EdaGitAddedIcon", name_hl = "TestColoredName" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- name_hl with visual attributes should be used directly
  MiniTest.expect.equality(entry.name_hl, "TestColoredName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestColoredName", {})
end

T["resolve_name_hl uses name_hl when group links to a group with visual attributes"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Set up a highlight group with link (simulating EdaGitIgnoredName -> EdaGitIgnored -> Comment)
  vim.api.nvim_set_hl(0, "TestLinkedBase", { fg = 0x808080 })
  vim.api.nvim_set_hl(0, "TestLinkedName", { link = "TestLinkedBase" })

  local decorations = {}
  decorations[2] = { suffix = "#", suffix_hl = "EdaGitIgnoredIcon", name_hl = "TestLinkedName" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- Linked name_hl that resolves to fg should be used
  MiniTest.expect.equality(entry.name_hl, "TestLinkedName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestLinkedBase", {})
  vim.api.nvim_set_hl(0, "TestLinkedName", {})
end

T["resolve_name_hl uses name_hl for directory when group has visual attributes"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Even for directories, a name_hl with visual attributes should override
  vim.api.nvim_set_hl(0, "TestIgnoredDirName", { fg = 0x808080 })

  local decorations = {}
  decorations[1] = { suffix = "#", suffix_hl = "EdaGitIgnoredIcon", name_hl = "TestIgnoredDirName" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[1].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  MiniTest.expect.equality(entry.name_hl, "TestIgnoredDirName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestIgnoredDirName", {})
end

-- =============================================
-- Rendering contract tests
-- Verify that decoration cache name_hl values resolve to actual visual attributes
-- on screen. This catches regressions where the pipeline produces highlight group
-- names that don't actually render (e.g., hl_group arrays that don't resolve links).
-- =============================================

---Check whether a highlight group name resolves to visual attributes.
---Uses nvim_get_hl with link=false to follow link chains.
---@param name string|string[]
---@return boolean
local function resolves_to_visual(name)
  if type(name) == "table" then
    -- Array hl_group: at least one element must resolve to visual attrs
    for _, n in ipairs(name) do
      if resolves_to_visual(n) then
        return true
      end
    end
    return false
  end
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return hl.fg ~= nil
    or hl.bg ~= nil
    or hl.sp ~= nil
    or hl.bold == true
    or hl.italic == true
    or hl.underline == true
    or hl.strikethrough == true
    or hl.reverse == true
end

T["decoration cache name_hl with visual attrs resolves to visible highlight"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Simulate EdaGitIgnoredName with link chain that has fg
  vim.api.nvim_set_hl(0, "TestVisualBase", { fg = 0x808080 })
  vim.api.nvim_set_hl(0, "TestVisualLinked", { link = "TestVisualBase" })

  local decorations = {}
  decorations[2] = { suffix = "#", suffix_hl = "Comment", name_hl = "TestVisualLinked" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- The cached name_hl must resolve to actual visual attributes
  -- This would fail if resolve_name_hl returned an array like { "EdaFileName", "TestVisualLinked" }
  -- because hl_group arrays don't resolve link chains in Neovim
  MiniTest.expect.equality(resolves_to_visual(entry.name_hl), true)
  -- And it must be the decoration's name_hl (not fallen back to base)
  MiniTest.expect.equality(entry.name_hl, "TestVisualLinked")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestVisualBase", {})
  vim.api.nvim_set_hl(0, "TestVisualLinked", {})
end

T["decoration cache name_hl for empty group falls back to base with visual attrs"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Empty highlight group (like default EdaGitUntrackedName = {})
  vim.api.nvim_set_hl(0, "TestEmptyGroup", {})

  local decorations = {}
  decorations[2] = { suffix = "?", suffix_hl = "Comment", name_hl = "TestEmptyGroup" }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- Should fall back to EdaFileName (base), not use the empty group
  MiniTest.expect.equality(entry.name_hl, "EdaFileName")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestEmptyGroup", {})
end

T["decoration cache name_hl resolves to array when multiple groups have visual attrs"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- Two groups with visual attrs: simulates git + cut coexistence
  vim.api.nvim_set_hl(0, "TestArrayGroupA", { fg = 0xff0000 })
  vim.api.nvim_set_hl(0, "TestArrayGroupB", { italic = true })

  local decorations = {}
  decorations[2] = { suffix = "#", suffix_hl = "Comment", name_hl = { "TestArrayGroupA", "TestArrayGroupB" } }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- With multiple visual-attr groups, name_hl is a string array for hl_group composition
  MiniTest.expect.equality(type(entry.name_hl), "table")
  MiniTest.expect.equality(entry.name_hl, { "TestArrayGroupA", "TestArrayGroupB" })

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestArrayGroupA", {})
  vim.api.nvim_set_hl(0, "TestArrayGroupB", {})
end

T["on_line emits per-element extmarks when name_hl is an array"] = function()
  -- Regression: Neovim's extmark does not resolve link chains inside hl_group arrays,
  -- so link-only groups like EdaMarkedName/EdaGitIgnoredName silently lose their fg
  -- when stacked. The fix emits one single-string extmark per array element with
  -- stair-stepped priority so each hl_group resolves its own link chain.
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local painter = Painter.new(buf)

  -- Two groups with direct visual attrs so has_visual_attrs keeps both in the array.
  vim.api.nvim_set_hl(0, "TestLayerA", { fg = 0x111111 })
  vim.api.nvim_set_hl(0, "TestLayerB", { fg = 0x222222 })

  local decorations = {}
  decorations[2] = { name_hl = { "TestLayerA", "TestLayerB" } }

  painter:paint(flat_lines, decorations)

  local captured = {}
  local orig_set_extmark = vim.api.nvim_buf_set_extmark
  vim.api.nvim_buf_set_extmark = function(b, n, row, col, opts)
    if b == buf and n == painter.ns_hl and opts and opts.hl_group and opts.end_col then
      table.insert(captured, {
        row = row,
        col = col,
        end_col = opts.end_col,
        hl_group = opts.hl_group,
        priority = opts.priority,
      })
    end
    return orig_set_extmark(b, n, row, col, opts)
  end

  -- Force the decoration provider to fire so on_line runs for every visible row.
  vim.api.nvim__redraw({ buf = buf, flush = true })

  vim.api.nvim_buf_set_extmark = orig_set_extmark

  -- Filter to the row that received the array decoration (flat_lines index 2 → row 1)
  local row_captured = {}
  for _, c in ipairs(captured) do
    if c.row == 1 then
      table.insert(row_captured, c)
    end
  end

  -- Expect two single-string extmarks, not one extmark with a table hl_group.
  MiniTest.expect.equality(#row_captured, 2)
  MiniTest.expect.equality(type(row_captured[1].hl_group), "string")
  MiniTest.expect.equality(type(row_captured[2].hl_group), "string")
  MiniTest.expect.equality(row_captured[1].hl_group, "TestLayerA")
  MiniTest.expect.equality(row_captured[2].hl_group, "TestLayerB")
  -- Later element wins overlapping attrs → higher priority.
  MiniTest.expect.equality(row_captured[1].priority < row_captured[2].priority, true)

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestLayerA", {})
  vim.api.nvim_set_hl(0, "TestLayerB", {})
end

T["decoration cache name_hl filters non-visual groups from array"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- One group with visual attrs, one without
  vim.api.nvim_set_hl(0, "TestFilterVisual", { fg = 0x00ff00 })
  vim.api.nvim_set_hl(0, "TestFilterEmpty", {})

  local decorations = {}
  decorations[2] = { suffix = "#", suffix_hl = "Comment", name_hl = { "TestFilterEmpty", "TestFilterVisual" } }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[flat_lines[2].node_id]
  MiniTest.expect.equality(entry ~= nil, true)
  -- Only 1 group passes has_visual_attrs, so result is a string (not array)
  MiniTest.expect.equality(type(entry.name_hl), "string")
  MiniTest.expect.equality(entry.name_hl, "TestFilterVisual")

  vim.api.nvim_buf_delete(buf, { force = true })
  vim.api.nvim_set_hl(0, "TestFilterVisual", {})
  vim.api.nvim_set_hl(0, "TestFilterEmpty", {})
end

-- =============================================
-- resolve_name_hl fallback for link-type nodes
-- =============================================

T["resolve_name_hl falls back to EdaSymlink for link-type node when decorator returns nil"] = function()
  local Node = require("eda.tree.node")
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local link_node = Node.create({ id = 99, name = "lnk", path = "/lnk", type = "link" })
  local flat_lines = { { node_id = 99, depth = 0, node = link_node } }
  local decorations = { [1] = {} }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[99]
  MiniTest.expect.equality(entry ~= nil, true)
  MiniTest.expect.equality(entry.name_hl, "EdaSymlink")

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["cache entry includes both link_suffix and suffix"] = function()
  local Node = require("eda.tree.node")
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  local link_node = Node.create({ id = 99, name = "lnk", path = "/lnk", type = "link", link_target = "/target" })
  local flat_lines = { { node_id = 99, depth = 0, node = link_node } }
  local decorations = {
    [1] = {
      suffix = "●",
      suffix_hl = "EdaGitModifiedIcon",
      link_suffix = "→ ../target",
      link_suffix_hl = "EdaSymlinkTarget",
    },
  }

  painter:paint(flat_lines, decorations)

  local entry = painter._decoration_cache[99]
  MiniTest.expect.equality(entry.suffix, "●")
  MiniTest.expect.equality(entry.suffix_hl, "EdaGitModifiedIcon")
  MiniTest.expect.equality(entry.link_suffix, "→ ../target")
  MiniTest.expect.equality(entry.link_suffix_hl, "EdaSymlinkTarget")

  vim.api.nvim_buf_delete(buf, { force = true })
end

-- paint_incremental tests

T["paint_incremental collapses subtree correctly"] = function()
  local store, root = build_store()
  -- Initial state: src/ is open, showing src/, src/init.lua, README.md (3 lines)
  local flat_lines_open = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)
  painter:paint(flat_lines_open)

  local lines_before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines_before, 3)

  -- Collapse src/
  local src_node = store:get(flat_lines_open[1].node_id)
  src_node.open = false
  local flat_lines_closed = Flatten.flatten(store, root)
  MiniTest.expect.equality(#flat_lines_closed, 2) -- src/, README.md

  local ok = painter:paint_incremental(flat_lines_closed, nil, {}, { toggled_node_id = src_node.id })
  MiniTest.expect.equality(ok, true)

  -- Verify buffer lines
  local lines_after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines_after, 2)
  MiniTest.expect.equality(lines_after[1]:find("src/") ~= nil, true)
  MiniTest.expect.equality(lines_after[2]:find("README.md") ~= nil, true)

  -- Verify ns_ids extmarks
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  MiniTest.expect.equality(#marks, 2)

  -- Verify snapshot
  local snapshot = painter:get_snapshot()
  for _, fl in ipairs(flat_lines_closed) do
    MiniTest.expect.equality(snapshot.entries[fl.node_id] ~= nil, true)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint_incremental expands subtree correctly"] = function()
  local store, root = build_store()
  -- Start with src/ collapsed
  local src_id = nil
  for _, node in pairs(store.nodes) do
    if node.name == "src" then
      node.open = false
      src_id = node.id
      break
    end
  end
  local flat_lines_closed = Flatten.flatten(store, root)
  MiniTest.expect.equality(#flat_lines_closed, 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)
  painter:paint(flat_lines_closed)

  -- Expand src/
  store:get(src_id).open = true
  local flat_lines_open = Flatten.flatten(store, root)
  MiniTest.expect.equality(#flat_lines_open, 3)

  local ok = painter:paint_incremental(flat_lines_open, nil, {}, { toggled_node_id = src_id })
  MiniTest.expect.equality(ok, true)

  -- Verify buffer lines
  local lines_after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines_after, 3)
  MiniTest.expect.equality(lines_after[1]:find("src/") ~= nil, true)
  MiniTest.expect.equality(lines_after[2]:find("init.lua") ~= nil, true)
  MiniTest.expect.equality(lines_after[2]:sub(1, 2), "  ") -- indented
  MiniTest.expect.equality(lines_after[3]:find("README.md") ~= nil, true)

  -- Verify ns_ids extmarks
  local ns = vim.api.nvim_create_namespace("eda_node_ids")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  MiniTest.expect.equality(#marks, 3)

  -- Verify snapshot
  local snapshot = painter:get_snapshot()
  for _, fl in ipairs(flat_lines_open) do
    MiniTest.expect.equality(snapshot.entries[fl.node_id] ~= nil, true)
  end

  vim.api.nvim_buf_delete(buf, { force = true })
end

T["paint_incremental returns false for invalid state"] = function()
  local store, root = build_store()
  local flat_lines = Flatten.flatten(store, root)
  local buf = vim.api.nvim_create_buf(false, true)
  local painter = Painter.new(buf)

  -- No prior paint — should return false
  local ok = painter:paint_incremental(flat_lines, nil, {}, { toggled_node_id = 999 })
  MiniTest.expect.equality(ok, false)
  -- Buffer should be empty (no mutation)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 1)
  MiniTest.expect.equality(lines[1], "")

  -- With prior paint but invalid hint
  painter:paint(flat_lines)
  ok = painter:paint_incremental(flat_lines, nil, {}, { toggled_node_id = 999 })
  MiniTest.expect.equality(ok, false)
  -- Buffer should be unchanged
  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  MiniTest.expect.equality(#lines, 3)

  vim.api.nvim_buf_delete(buf, { force = true })
end

return T
