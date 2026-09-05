local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

-- Geometry of one explorer's overlay relative to its owner window, plus the state
-- flags the suspension rules act on. Returned as plain data so assertions read as
-- numbers rather than as screen scraping.
local OVERLAY_REPORT = [[
  local out = {}
  for i, e in ipairs(require("eda").get_all()) do
    local p = e.preview
    local row = {
      kind = e.window.kind,
      enabled = p:is_enabled(),
      suspended = p:_is_suspended(),
      open = p.winid ~= nil and vim.api.nvim_win_is_valid(p.winid),
    }
    if row.open then
      local op = vim.api.nvim_win_get_position(e.window.winid)
      local winbar = vim.fn.getwininfo(e.window.winid)[1].winbar or 0
      local oh = vim.api.nvim_win_get_height(e.window.winid) - winbar
      local ow = vim.api.nvim_win_get_width(e.window.winid)
      local fp = vim.api.nvim_win_get_position(p.winid)
      local fw = vim.api.nvim_win_get_width(p.winid)
      local fh = vim.api.nvim_win_get_height(p.winid)
      row.inside = fp[1] >= op[1] + winbar
        and fp[1] + fh + 1 <= op[1] + winbar + oh - 1
        and fp[2] >= op[2]
        and fp[2] + fw + 1 <= op[2] + ow - 1
      row.overlay_col = fp[2]
      row.first_line = vim.api.nvim_buf_get_lines(p.bufnr, 0, 1, false)[1] or ""
    end
    out[i] = row
  end
  return out
]]

local function report()
  return e2e.exec(child, OVERLAY_REPORT)
end

-- Only non-float windows count as layout: the overlay itself is a float and must not
-- be mistaken for a split.
local NORMAL_WINDOWS = [[
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      table.insert(out, w .. ":" .. vim.api.nvim_win_get_width(w))
    end
  end
  table.sort(out)
  return out
]]

local function normal_windows()
  return e2e.exec(child, NORMAL_WINDOWS)
end

---Dispatch `action_name` against the explorer at `index` in `eda.get_all()`.
local function dispatch(index, action_name)
  e2e.exec(
    child,
    string.format(
      [[
    local action, eda = require("eda.action"), require("eda")
    local e = eda.get_all()[%d]
    action.dispatch(%q, {
      store = e.store, buffer = e.buffer, window = e.window,
      scanner = e.scanner, config = require("eda.config").get(), explorer = e,
    })
  ]],
      index,
      action_name
    )
  )
end

---Put the explorer at `index` on the row rendering `path` and wait until its preview
---actually shows `expected_first_line`.
---The window is made current first: CursorMoved does not fire for a window that is
---not the current one. Waiting on the content rather than on the window handle matters
---too, because the preview may already be open on a different target.
local function focus_path(index, path, expected_first_line)
  e2e.exec(
    child,
    string.format(
      [[
    local e = require("eda").get_all()[%d]
    for row, fl in ipairs(e.buffer.flat_lines) do
      local node = e.store:get(fl.node_id)
      if node and node.path == %q then
        vim.api.nvim_set_current_win(e.window.winid)
        vim.api.nvim_win_set_cursor(e.window.winid, { row, 0 })
        return true
      end
    end
    error("no row renders " .. %q)
  ]],
      index,
      path,
      path
    )
  )
  e2e.wait_until(
    child,
    string.format(
      [[
    local p = require("eda").get_all()[%d].preview
    if p.winid == nil or not vim.api.nvim_win_is_valid(p.winid) then
      return false
    end
    return vim.api.nvim_buf_get_lines(p.bufnr, 0, 1, false)[1] == %q
  ]],
      index,
      expected_first_line
    ),
    10000
  )
end

---Give the two explorers different preview targets and wait for both to render.
---Targets are named rather than addressed by row: putting the cursor on the row it
---already occupies fires no CursorMoved, so a row-based helper can leave a preview
---showing whatever it had before.
local function focus_distinct_targets()
  e2e.wait_until(
    child,
    [[
    for _, e in ipairs(require("eda").get_all()) do
      if vim.api.nvim_buf_line_count(e.buffer.bufnr) < 2 then
        return false
      end
    end
    return true
  ]],
    10000
  )
  focus_path(1, tmp .. "/alpha.txt", "ALPHA")
  focus_path(2, tmp .. "/beta.txt", "BETA")
end

local function split_explorer()
  dispatch(1, "split")
  e2e.wait_until(child, "#require('eda').get_all() == 2", 10000)
end

T["replace preview"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child, [[{ window = { kind = "replace" }, preview = { enabled = true, debounce = 0 } }]])
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/alpha.txt", "ALPHA")
      e2e.create_file(tmp .. "/beta.txt", "BETA")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["replace preview"]["an explicit replace explorer opens an overlay inside its own window"] = function()
  e2e.open_eda(child, tmp)
  local layout_before = normal_windows()

  e2e.exec(child, [[vim.api.nvim_win_set_cursor(0, { 1, 0 })]])
  e2e.wait_until(child, "require('eda').get_current().preview.winid ~= nil", 10000)

  local rows = report()
  MiniTest.expect.equality(rows[1].kind, "replace")
  MiniTest.expect.equality(rows[1].open, true)
  MiniTest.expect.equality(rows[1].inside, true)
  -- The overlay is a float: it adds no split and resizes no existing window.
  MiniTest.expect.equality(normal_windows(), layout_before)
end

T["replace preview"]["the overlay closes when the explorer buffer leaves its window"] = function()
  e2e.open_eda(child, tmp)
  e2e.wait_until(child, "require('eda').get_current().preview.winid ~= nil", 10000)

  -- `select` opens the file in the same window, so the window stays valid while the
  -- explorer buffer is swapped out from under the overlay.
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp .. "/alpha.txt"))
  e2e.wait_until(child, "require('eda').get_all()[1].preview.winid == nil", 10000)

  local rows = report()
  MiniTest.expect.equality(rows[1].open, false)
end

T["replace preview"]["two replace explorers preview independently"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()

  focus_distinct_targets()

  local rows = report()
  MiniTest.expect.equality(rows[1].inside, true)
  MiniTest.expect.equality(rows[2].inside, true)
  MiniTest.expect.equality(rows[1].first_line ~= rows[2].first_line, true)
end

T["replace preview"]["entering insert mode hides only the acting explorer's overlay"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()
  focus_distinct_targets()
  e2e.exec(child, [[vim.api.nvim_set_current_win(require("eda").get_all()[2].window.winid)]])

  e2e.feed(child, "i")
  e2e.wait_until(child, "require('eda').get_all()[2].preview:_is_suspended()", 10000)

  local hidden = report()
  MiniTest.expect.equality(hidden[2].open, false)
  -- Suspension is temporary: the user's toggle choice is untouched.
  MiniTest.expect.equality(hidden[2].enabled, true)
  MiniTest.expect.equality(hidden[1].open, true)
  MiniTest.expect.equality(hidden[1].suspended, false)

  e2e.feed(child, "<Esc>")
  e2e.wait_until(child, "require('eda').get_all()[2].preview.winid ~= nil", 10000)

  local restored = report()
  MiniTest.expect.equality(restored[2].inside, true)
  MiniTest.expect.equality(restored[2].suspended, false)
end

-- The classifier reads mode(1), so the modes that differ most from plain Insert are the
-- ones worth driving end to end: gR reports "Rv", which no ModeChanged "R" pattern
-- matches, and Visual is where the case-insensitive pattern trap lived.
for _, case in ipairs({
  { keys = "gR", mode = "Rv", label = "virtual replace" },
  { keys = "v", mode = "v", label = "visual" },
}) do
  T["replace preview"][case.label .. " mode hides only the acting explorer's overlay"] = function()
    e2e.open_eda(child, tmp)
    split_explorer()
    focus_distinct_targets()
    e2e.exec(child, [[vim.api.nvim_set_current_win(require("eda").get_all()[2].window.winid)]])

    e2e.feed(child, case.keys)
    e2e.wait_until(child, string.format("vim.fn.mode(1) == %q", case.mode), 10000)
    e2e.wait_until(child, "require('eda').get_all()[2].preview:_is_suspended()", 10000)

    local hidden = report()
    MiniTest.expect.equality(hidden[2].open, false)
    MiniTest.expect.equality(hidden[2].enabled, true)
    MiniTest.expect.equality(hidden[1].open, true)
    MiniTest.expect.equality(hidden[1].suspended, false)

    e2e.feed(child, "<Esc>")
    e2e.wait_until(child, "require('eda').get_all()[2].preview.winid ~= nil", 10000)
    MiniTest.expect.equality(report()[2].inside, true)
  end
end

T["replace preview"]["a too narrow owner suspends the overlay and widening brings it back"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()
  e2e.exec(
    child,
    [[
    vim.api.nvim_set_current_win(require("eda").get_all()[2].window.winid)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]]
  )
  e2e.wait_until(child, "require('eda').get_all()[2].preview.winid ~= nil", 10000)

  e2e.exec(child, [[vim.cmd("vertical resize 25")]])
  e2e.wait_until(child, "require('eda').get_all()[2].preview.winid == nil", 10000)
  -- Hiding for lack of room leaves the user's toggle choice alone.
  MiniTest.expect.equality(report()[2].enabled, true)

  e2e.exec(child, [[vim.cmd("vertical resize 100")]])
  e2e.wait_until(child, "require('eda').get_all()[2].preview.winid ~= nil", 10000)
  MiniTest.expect.equality(report()[2].inside, true)
end

T["replace preview"]["the overlay follows a pure window move"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()
  focus_distinct_targets()
  local before = report()

  -- `wincmd x` swaps two windows without changing their sizes and emits no resize
  -- autocmd at all, so only the decoration provider can notice it.
  e2e.exec(child, [[vim.cmd("wincmd x")]])
  e2e.wait_until(
    child,
    string.format(
      [[
    local all = require("eda").get_all()
    local p = all[1].preview
    return p.winid ~= nil and vim.api.nvim_win_get_position(p.winid)[2] ~= %d
  ]],
      before[1].overlay_col
    ),
    10000
  )

  local after = report()
  MiniTest.expect.equality(after[1].inside, true)
  MiniTest.expect.equality(after[2].inside, true)
end

T["replace preview"]["toggling one overlay leaves the other alone and restores the window layout"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()
  focus_distinct_targets()
  local layout_before = normal_windows()

  dispatch(1, "toggle_preview")
  e2e.wait_until(child, "require('eda').get_all()[1].preview.winid == nil", 10000)

  local rows = report()
  MiniTest.expect.equality(rows[1].enabled, false)
  MiniTest.expect.equality(rows[2].enabled, true)
  MiniTest.expect.equality(rows[2].open, true)

  -- Normal window ids and widths are untouched by opening and closing the overlay.
  MiniTest.expect.equality(normal_windows(), layout_before)
end

T["replace preview"]["scrolling one overlay leaves the other alone"] = function()
  e2e.create_file(tmp .. "/long.txt", string.rep("line\n", 200))
  e2e.open_eda(child, tmp)
  split_explorer()
  -- The scrolled explorer needs a file long enough to scroll; a one-line preview
  -- would satisfy the isolation assertion no matter what the scroll action did.
  focus_path(1, tmp .. "/long.txt", "line")
  focus_path(2, tmp .. "/alpha.txt", "ALPHA")

  local TOP_LINES = [[
    local out = {}
    for i, e in ipairs(require("eda").get_all()) do
      out[i] = vim.api.nvim_win_call(e.preview.winid, function()
        return vim.fn.line("w0")
      end)
    end
    return out
  ]]
  local before = e2e.exec(child, TOP_LINES)
  dispatch(1, "preview_scroll_page_down")
  local after = e2e.exec(child, TOP_LINES)

  MiniTest.expect.equality(after[1] > before[1], true)
  MiniTest.expect.equality(after[2], before[2])
end

T["replace preview"]["copy in one explorer pastes into the other with both overlays open"] = function()
  e2e.create_dir(tmp .. "/target")
  e2e.open_eda(child, tmp)
  split_explorer()
  focus_distinct_targets()

  e2e.exec(
    child,
    string.format(
      [[
    local action, eda = require("eda.action"), require("eda")
    local function ctx_for(e)
      return { store = e.store, buffer = e.buffer, window = e.window,
               scanner = e.scanner, config = require("eda.config").get(), explorer = e }
    end
    local all = eda.get_all()

    -- Copy alpha.txt from the first explorer.
    local source = all[1]
    for row, fl in ipairs(source.buffer.flat_lines) do
      local node = source.store:get(fl.node_id)
      if node and node.path == %q then
        vim.api.nvim_win_set_cursor(source.window.winid, { row, 0 })
        break
      end
    end
    action.dispatch("copy", ctx_for(source))

    -- Paste into the target directory from the second explorer.
    local dest = all[2]
    for row, fl in ipairs(dest.buffer.flat_lines) do
      local node = dest.store:get(fl.node_id)
      if node and node.path == %q then
        vim.api.nvim_win_set_cursor(dest.window.winid, { row, 0 })
        break
      end
    end
    action.dispatch("paste", ctx_for(dest))
    return true
  ]],
      tmp .. "/alpha.txt",
      tmp .. "/target"
    )
  )
  e2e.wait_until(child, string.format([[return vim.uv.fs_stat(%q) ~= nil]], tmp .. "/target/alpha.txt"), 10000)

  -- Both overlays survive the file operation.
  local rows = report()
  MiniTest.expect.equality(rows[1].open, true)
  MiniTest.expect.equality(rows[2].open, true)
end

T["replace preview"]["open_replace carries a float explorer into an overlay"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false }, icon = { provider = "none" }, header = false,
      confirm = false, delete_to_trash = false,
      window = { kind = "float" }, preview = { enabled = true, debounce = 0 },
    })
  ]]
  )
  e2e.open_eda(child, tmp)
  e2e.wait_until(child, [[return require("eda").get_current().window.kind == "float"]], 10000)

  dispatch(1, "open_replace")
  e2e.wait_until(child, [[return require("eda").get_current().window.kind == "replace"]], 10000)

  e2e.exec(child, [[vim.api.nvim_win_set_cursor(require("eda").get_current().window.winid, { 1, 0 })]])
  e2e.wait_until(child, "require('eda').get_current().preview.winid ~= nil", 10000)
  MiniTest.expect.equality(report()[1].inside, true)
end

T["replace preview"]["netrw hijack opens an overlay for a directory buffer"] = function()
  e2e.exec(
    child,
    [[
    pcall(vim.api.nvim_del_augroup_by_name, "FileExplorer")
    require("eda").setup({
      hijack_netrw = true,
      git = { enabled = false }, icon = { provider = "none" }, header = false,
      confirm = false, delete_to_trash = false,
      preview = { enabled = true, debounce = 0 },
    })
  ]]
  )
  e2e.exec(child, string.format([[vim.cmd.edit(vim.fn.fnameescape(%q))]], tmp))
  e2e.wait_until(child, [[return require("eda").get_current() ~= nil]], 10000)
  e2e.wait_until(child, [[return require("eda").get_current().window.kind == "replace"]], 10000)

  e2e.exec(child, [[vim.api.nvim_win_set_cursor(require("eda").get_current().window.winid, { 1, 0 })]])
  e2e.wait_until(child, "require('eda').get_current().preview.winid ~= nil", 10000)
  MiniTest.expect.equality(report()[1].inside, true)
end

T["replace preview"]["closing the owner window removes its overlay and leaves the other"] = function()
  e2e.open_eda(child, tmp)
  split_explorer()
  focus_distinct_targets()

  e2e.exec(
    child,
    [[
    local e = require("eda").get_all()[2]
    vim.api.nvim_set_current_win(e.window.winid)
    vim.cmd("close")
  ]]
  )
  e2e.wait_until(child, "require('eda').get_all()[2].preview.winid == nil", 10000)

  -- Preview:close() nils its handle before closing the window, so the Lua-side state
  -- alone would not notice a float left on screen; count the floats instead.
  local floats = e2e.exec(
    child,
    [[
    local n = 0
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        n = n + 1
      end
    end
    return n
  ]]
  )
  MiniTest.expect.equality(floats, 1)

  -- The surviving explorer keeps its overlay and stays inside its own window.
  MiniTest.expect.equality(report()[1].inside, true)
end

return T
