local Preview = require("eda.preview")
local config = require("eda.config")
local helpers = require("helpers")

local T = MiniTest.new_set()

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

T["Preview _current_path tracks shown file"] = function()
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
    return p._current_path ~= nil
  end)
  MiniTest.expect.equality(p._current_path, test_file)
  p:close()
  cleanup({ { win = filer_winid, buf = filer_buf } })
  helpers.remove_temp_dir(temp_dir)
end

T["Preview _pending_path is set synchronously"] = function()
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
  MiniTest.expect.equality(p._pending_path, test_file)
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

return T
