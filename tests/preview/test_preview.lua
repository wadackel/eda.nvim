local Preview = require("eda.preview")
local config = require("eda.config")
local helpers = require("helpers")
local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local decorator_mod = require("eda.render.decorator")

local T = MiniTest.new_set()

-- Build a Store + Scanner + decorator chain rooted at `root_path`, mirroring
-- the production decorator chain in lua/eda/init.lua. Returns store, scanner,
-- chain, and a callback-style scan-root to await initial scan completion.
local function build_tree_deps(root_path, cfg)
  local store = Store.new()
  store:set_root(root_path)
  local scanner = Scanner.new(store, cfg)
  local chain = decorator_mod.Chain.new()
  chain:add(decorator_mod.icon_decorator)
  chain:add(decorator_mod.symlink_decorator)
  if cfg.git and cfg.git.enabled then
    chain:add(decorator_mod.dotgit_decorator)
    chain:add(decorator_mod.git_decorator)
  end
  chain:add(decorator_mod.cut_decorator)
  chain:add(decorator_mod.mark_decorator)
  return store, scanner, chain
end

-- Helper: synchronously scan a directory node and wait for completion (test only).
local function scan_sync(scanner, node_id, timeout_ms)
  local done = false
  scanner:scan(node_id, function()
    done = true
  end)
  helpers.wait_for(timeout_ms or 2000, function()
    return done
  end)
  return done
end

-- Helper: build a buffer of preview body lines (excluding the painter header).
local function preview_body_lines(p)
  if not p.bufnr or not vim.api.nvim_buf_is_valid(p.bufnr) then
    return {}
  end
  local offset = p.painter and p.painter.header_lines or 0
  return vim.api.nvim_buf_get_lines(p.bufnr, offset, -1, false)
end

-- Helper: create a float window simulating the filer
local function open_filer_float(cfg)
  local Window = require("eda.window")
  local buf = vim.api.nvim_create_buf(false, true)
  local layout = Window._compute_layout("float", cfg)
  local winid = vim.api.nvim_open_win(buf, true, layout)
  return winid, buf
end

-- Helper: create a split window simulating the filer
local function open_filer_split(cfg)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.cmd("topleft vsplit")
  local winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, buf)
  local kind_opts = cfg.window.kinds.split_left or {}
  local raw = tostring(kind_opts.width or "30%")
  local pct_str = (raw:gsub("%%$", ""))
  local pct = tonumber(pct_str) or 30
  local width = math.floor(vim.o.columns * pct / 100)
  vim.api.nvim_win_set_width(winid, width)
  return winid, buf
end

-- Helper: cleanup windows and buffers
local function cleanup(items)
  for _, item in ipairs(items) do
    if item.win and vim.api.nvim_win_is_valid(item.win) then
      vim.api.nvim_win_close(item.win, true)
    end
    if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
      vim.api.nvim_buf_delete(item.buf, { force = true })
    end
  end
end

-- PR-1: Preview.new() initial state
T["Preview.new initial state"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  MiniTest.expect.equality(p.window, nil)
  MiniTest.expect.equality(p.winid, nil)
  MiniTest.expect.equality(p.bufnr, nil)
end

-- PR-2: attach sets window reference
T["Preview:attach sets window"] = function()
  config.setup()
  local mock_window = { winid = nil, kind = "split_left", config = config.get() }
  local p = Preview.new(config.get().preview)
  p:attach(mock_window)
  MiniTest.expect.equality(p.window, mock_window)
end

-- PR-6: close is idempotent
T["Preview:close is idempotent"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  p:close()
  p:close()
  MiniTest.expect.equality(p.winid, nil)
end

-- PR-7: show before attach does not error (nil guard)
T["Preview:show before attach does not error"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello")
  p:show(test_file)
  MiniTest.expect.equality(p.winid, nil)
  helpers.remove_temp_dir(temp_dir)
end

T["Preview show close lifecycle"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  MiniTest.expect.equality(p.winid ~= nil, true)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(p.winid), true)
  p:close()
  MiniTest.expect.equality(p.winid, nil)
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview show close show re-creates window"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  local first_winid = p.winid
  p:close()
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  local second_winid = p.winid
  MiniTest.expect.equality(second_winid ~= nil, true)
  MiniTest.expect.equality(first_winid ~= second_winid, true)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview float mode show shrinks filer"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_float(cfg)
  local original_width = vim.api.nvim_win_get_width(filer_winid)
  local mock_window = { winid = filer_winid, kind = "float", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  local new_width = vim.api.nvim_win_get_width(filer_winid)
  MiniTest.expect.equality(new_width < original_width, true)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview float mode close restores filer"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_float(cfg)
  local original_width = vim.api.nvim_win_get_width(filer_winid)
  local mock_window = { winid = filer_winid, kind = "float", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  p:close()
  local restored_width = vim.api.nvim_win_get_width(filer_winid)
  MiniTest.expect.equality(restored_width, original_width)
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview split_left does not change filer size"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local original_width = vim.api.nvim_win_get_width(filer_winid)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  local after_width = vim.api.nvim_win_get_width(filer_winid)
  MiniTest.expect.equality(after_width, original_width)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview reposition no-op when hidden"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  p:reposition()
  MiniTest.expect.equality(p.winid, nil)
end

T["Preview reposition keeps preview valid"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(p.winid), true)
  p:reposition()
  MiniTest.expect.equality(vim.api.nvim_win_is_valid(p.winid), true)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview scroll_down returns false when hidden"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  MiniTest.expect.equality(p:scroll_down(), false)
end

T["Preview scroll_up returns false when hidden"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  MiniTest.expect.equality(p:scroll_up(), false)
end

T["Preview scroll_page_down returns false when hidden"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  MiniTest.expect.equality(p:scroll_page_down(), false)
end

T["Preview scroll_page_up returns false when hidden"] = function()
  config.setup()
  local p = Preview.new(config.get().preview)
  MiniTest.expect.equality(p:scroll_page_up(), false)
end

T["Preview _current_target tracks shown file"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p._current_target ~= nil
  end)
  MiniTest.expect.equality(p._current_target, test_file)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview _pending_target is set synchronously"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  MiniTest.expect.equality(p._pending_target, test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview scroll returns true when visible"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  local p = Preview.new(cfg.preview)
  local temp_dir = helpers.create_temp_dir()
  local test_file = temp_dir .. "/test.txt"
  helpers.create_file(test_file, "hello world")
  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window)
  p:show(test_file)
  helpers.wait_for(1000, function()
    return p.winid ~= nil
  end)
  MiniTest.expect.equality(p:scroll_down(), true)
  MiniTest.expect.equality(p:scroll_up(), true)
  MiniTest.expect.equality(p:scroll_page_down(), true)
  MiniTest.expect.equality(p:scroll_page_up(), true)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

-- PR-D1: closed directory preview shows direct children only (1 level deep).
T["PR-D1 closed dir preview shows 1 level"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.git.enabled = false
  local p = Preview.new(cfg.preview)

  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/sub/b")
  helpers.create_file(tmp .. "/sub/a.txt", "alpha")
  helpers.create_file(tmp .. "/sub/b/c.txt", "grandchild")

  local store, scanner, chain = build_tree_deps(tmp, cfg)
  scan_sync(scanner, store.root_id)
  local sub_node = store:get_by_path(tmp .. "/sub")
  MiniTest.expect.no_equality(sub_node, nil)
  scan_sync(scanner, sub_node.id) -- one level: sub is loaded; sub/b remains unloaded

  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window, { store = store, scanner = scanner, decorator_chain = chain })
  p:show_directory(sub_node)
  helpers.wait_for(2000, function()
    return p.winid ~= nil
  end)

  MiniTest.expect.equality(p.winid ~= nil, true)
  local body = preview_body_lines(p)
  local joined = table.concat(body, "\n")
  MiniTest.expect.equality(joined:find("a.txt", 1, true) ~= nil, true)
  MiniTest.expect.equality(joined:find("b/", 1, true) ~= nil, true)
  -- Grandchild must not be visible (sub/b is unloaded)
  MiniTest.expect.equality(joined:find("c.txt", 1, true), nil)

  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(tmp)
end

-- PR-D2: open directory preview mirrors the main tree's expanded subtree.
T["PR-D2 open dir preview mirrors expanded subtree"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.git.enabled = false
  local p = Preview.new(cfg.preview)

  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/sub/b")
  helpers.create_dir(tmp .. "/sub/d")
  helpers.create_file(tmp .. "/sub/a.txt", "alpha")
  helpers.create_file(tmp .. "/sub/b/c.txt", "beta-child")
  helpers.create_file(tmp .. "/sub/d/e.txt", "delta-child")

  local store, scanner, chain = build_tree_deps(tmp, cfg)
  scan_sync(scanner, store.root_id)
  local sub = store:get_by_path(tmp .. "/sub")
  scan_sync(scanner, sub.id)
  local sub_b = store:get_by_path(tmp .. "/sub/b")
  scan_sync(scanner, sub_b.id)
  local sub_d = store:get_by_path(tmp .. "/sub/d")
  scan_sync(scanner, sub_d.id)

  -- Mark sub and sub/b as open; sub/d remains closed
  sub.open = true
  sub_b.open = true

  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window, { store = store, scanner = scanner, decorator_chain = chain })
  p:show_directory(sub)
  helpers.wait_for(2000, function()
    return p.winid ~= nil
  end)

  local body = preview_body_lines(p)
  local joined = table.concat(body, "\n")
  -- Open subtree expanded: a.txt, b/, c.txt visible
  MiniTest.expect.equality(joined:find("a.txt", 1, true) ~= nil, true)
  MiniTest.expect.equality(joined:find("b/", 1, true) ~= nil, true)
  MiniTest.expect.equality(joined:find("c.txt", 1, true) ~= nil, true)
  -- Closed sibling d/ visible but its children are not
  MiniTest.expect.equality(joined:find("d/", 1, true) ~= nil, true)
  MiniTest.expect.equality(joined:find("e.txt", 1, true), nil)

  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(tmp)
end

-- PR-D3: file → dir → file transition leaves no stale filetype or painter state.
T["PR-D3 file dir file transition cleans state"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.git.enabled = false
  local p = Preview.new(cfg.preview)

  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/x.lua", "local M = {}\nreturn M\n")
  helpers.create_dir(tmp .. "/sub")
  helpers.create_file(tmp .. "/sub/inside.txt", "hi")

  local store, scanner, chain = build_tree_deps(tmp, cfg)
  scan_sync(scanner, store.root_id)
  local sub = store:get_by_path(tmp .. "/sub")
  scan_sync(scanner, sub.id)

  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window, { store = store, scanner = scanner, decorator_chain = chain })

  -- 1) File first → filetype lua
  p:show(tmp .. "/x.lua")
  helpers.wait_for(2000, function()
    return p.winid ~= nil
  end)
  MiniTest.expect.equality(vim.bo[p.bufnr].filetype, "lua")

  -- 2) Switch to directory → filetype cleared, painter populated
  p:show_directory(sub)
  helpers.wait_for(1000, function()
    return p.painter and #p.painter._flat_lines > 0
  end)
  MiniTest.expect.equality(vim.bo[p.bufnr].filetype, "")
  MiniTest.expect.equality(#p.painter._flat_lines > 0, true)

  -- 3) Switch back to file → painter state cleared, no icon extmarks
  p:show(tmp .. "/x.lua")
  helpers.wait_for(2000, function()
    return vim.bo[p.bufnr].filetype == "lua"
  end)
  MiniTest.expect.equality(#p.painter._flat_lines, 0)
  local icon_marks = vim.api.nvim_buf_get_extmarks(p.bufnr, p.painter.ns_icon, 0, -1, {})
  MiniTest.expect.equality(#icon_marks, 0)

  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(tmp)
end

-- PR-D4: closed dir whose children_state is "unloaded" triggers an async scan
-- and renders once the scan settles.
T["PR-D4 closed dir async scan path"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.git.enabled = false
  local p = Preview.new(cfg.preview)

  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_dir(tmp .. "/sub")
  helpers.create_file(tmp .. "/sub/x.txt", "x")

  local store, scanner, chain = build_tree_deps(tmp, cfg)
  scan_sync(scanner, store.root_id)
  local sub = store:get_by_path(tmp .. "/sub")
  MiniTest.expect.no_equality(sub, nil)
  -- Sub has not been scanned yet → children_state must be "unloaded"
  MiniTest.expect.equality(sub.children_state, "unloaded")

  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window, { store = store, scanner = scanner, decorator_chain = chain })

  p:show_directory(sub)
  helpers.wait_for(3000, function()
    return p.winid ~= nil
  end)

  MiniTest.expect.equality(p.winid ~= nil, true)
  local body = preview_body_lines(p)
  local joined = table.concat(body, "\n")
  MiniTest.expect.equality(joined:find("x.txt", 1, true) ~= nil, true)
  -- Side-effect: main store now has the dir loaded (user accepted this in /plan).
  MiniTest.expect.equality(store:get(sub.id).children_state, "loaded")

  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(tmp)
end

-- PR-D5: debounce keeps only the latest update target — switching from a file
-- to a dir within the debounce window must render the dir, not the file.
T["PR-D5 debounce target switch keeps latest"] = function()
  config.setup()
  local cfg = config.get()
  cfg.preview.enabled = true
  cfg.preview.debounce = 50
  cfg.git.enabled = false
  local p = Preview.new(cfg.preview)

  local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
  helpers.create_file(tmp .. "/f.txt", "FILE_CONTENT_MARKER")
  helpers.create_dir(tmp .. "/sub")
  helpers.create_file(tmp .. "/sub/a.txt", "alpha")

  local store, scanner, chain = build_tree_deps(tmp, cfg)
  scan_sync(scanner, store.root_id)
  local sub = store:get_by_path(tmp .. "/sub")
  scan_sync(scanner, sub.id)
  local file_node = store:get_by_path(tmp .. "/f.txt")

  local filer_winid, filer_buf = open_filer_split(cfg)
  local mock_window = { winid = filer_winid, kind = "split_left", config = cfg }
  p:attach(mock_window, { store = store, scanner = scanner, decorator_chain = chain })

  -- Fire two updates back-to-back; the dir update is the latest one.
  p:update(file_node)
  p:update(sub)

  helpers.wait_for(2000, function()
    return p.painter and #p.painter._flat_lines > 0
  end)

  local body = preview_body_lines(p)
  local joined = table.concat(body, "\n")
  -- Latest target (sub) rendered; file content marker absent.
  MiniTest.expect.equality(joined:find("a.txt", 1, true) ~= nil, true)
  MiniTest.expect.equality(joined:find("FILE_CONTENT_MARKER", 1, true), nil)

  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(tmp)
end

return T
