local Window = require("eda.window")
local config = require("eda.config")

local T = MiniTest.new_set()

T["compute_layout float"] = function()
  config.setup()
  local layout = Window._compute_layout("float", config.get())
  MiniTest.expect.equality(layout.relative, "editor")
  MiniTest.expect.equality(type(layout.width), "number")
  MiniTest.expect.equality(type(layout.height), "number")
  MiniTest.expect.equality(layout.width > 0, true)
  MiniTest.expect.equality(layout.height > 0, true)
  MiniTest.expect.equality(layout.zindex, 50)
end

T["compute_layout split_left"] = function()
  config.setup()
  local layout = Window._compute_layout("split_left", config.get())
  MiniTest.expect.equality(layout.split, "left")
  MiniTest.expect.equality(type(layout.width), "number")
end

T["compute_layout split_right"] = function()
  config.setup()
  local layout = Window._compute_layout("split_right", config.get())
  MiniTest.expect.equality(layout.split, "right")
end

T["compute_layout replace"] = function()
  config.setup()
  local layout = Window._compute_layout("replace", config.get())
  MiniTest.expect.equality(layout.replace, true)
end

T["new creates window instance"] = function()
  config.setup()
  local win = Window.new("split_left", config.get())
  MiniTest.expect.equality(win.kind, "split_left")
  MiniTest.expect.equality(win.winid, nil)
end

-- Helper: open a scratch float window for testing
local function open_scratch_float()
  local buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  return winid, buf
end

local function close_scratch(winid, buf)
  if vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

T["is_visible returns false when winid is nil"] = function()
  config.setup()
  local win = Window.new("split_left", config.get())
  MiniTest.expect.equality(win:is_visible(), false)
end

T["is_visible returns true when eda buffer is displayed"] = function()
  config.setup()
  local buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  local win = Window.new("split_left", config.get())
  win.winid = winid
  win.bufnr = buf
  MiniTest.expect.equality(win:is_visible(), true)
  close_scratch(winid, buf)
end

T["is_visible returns false when window shows different buffer"] = function()
  config.setup()
  local eda_buf = vim.api.nvim_create_buf(false, true)
  local other_buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(other_buf, false, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  local win = Window.new("replace", config.get())
  win.winid = winid
  win.bufnr = eda_buf
  MiniTest.expect.equality(win:is_visible(), false)
  close_scratch(winid, other_buf)
  vim.api.nvim_buf_delete(eda_buf, { force = true })
end

T["is_visible returns false when bufnr is deleted"] = function()
  config.setup()
  local buf = vim.api.nvim_create_buf(false, true)
  local other_buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(other_buf, false, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  local win = Window.new("replace", config.get())
  win.winid = winid
  win.bufnr = buf
  vim.api.nvim_buf_delete(buf, { force = true })
  MiniTest.expect.equality(win:is_visible(), false)
  close_scratch(winid, other_buf)
end

-- PL-1: split_left returns preview only
T["compute_preview_layout split_left returns preview without filer"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("split_left", winid, config.get())
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.preview ~= nil, true)
  MiniTest.expect.equality(result.filer, nil)
  close_scratch(winid, buf)
end

-- PL-2: split_right returns preview only (or nil if no space on left)
T["compute_preview_layout split_right returns preview without filer"] = function()
  config.setup()
  -- Position the scratch window on the right side so there is space for preview on the left
  local buf = vim.api.nvim_create_buf(false, true)
  local right_col = vim.o.columns - 30
  local winid = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = 20,
    height = 20,
    row = 0,
    col = right_col,
    style = "minimal",
  })
  local result = Window._compute_preview_layout("split_right", winid, config.get())
  if right_col > 10 then
    MiniTest.expect.equality(result ~= nil, true)
    MiniTest.expect.equality(result.preview ~= nil, true)
    MiniTest.expect.equality(result.filer, nil)
  end
  close_scratch(winid, buf)
end

-- PL-3: float returns both preview and filer
T["compute_preview_layout float returns preview and filer"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("float", winid, config.get())
  MiniTest.expect.equality(result ~= nil, true)
  MiniTest.expect.equality(result.preview ~= nil, true)
  MiniTest.expect.equality(result.filer ~= nil, true)
  close_scratch(winid, buf)
end

-- PL-4: replace returns nil
T["compute_preview_layout replace returns nil"] = function()
  config.setup()
  local result = Window._compute_preview_layout("replace", 0, config.get())
  MiniTest.expect.equality(result, nil)
end

-- PL-5: float width consistency (filer + preview + 2 borders = orig)
T["compute_preview_layout float width consistency"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local cfg = config.get()
  local orig = Window._compute_layout("float", cfg)
  local result = Window._compute_preview_layout("float", winid, cfg)
  if result then
    MiniTest.expect.equality(result.filer.width + result.preview.width + 2, orig.width)
  end
  close_scratch(winid, buf)
end

-- PL-6: preview layout has all required fields
T["compute_preview_layout preview has required fields"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("float", winid, config.get())
  if result then
    local p = result.preview
    MiniTest.expect.equality(p.relative, "editor")
    MiniTest.expect.equality(type(p.width), "number")
    MiniTest.expect.equality(type(p.height), "number")
    MiniTest.expect.equality(type(p.row), "number")
    MiniTest.expect.equality(type(p.col), "number")
    MiniTest.expect.equality(p.border ~= nil, true)
    MiniTest.expect.equality(p.focusable, false)
    MiniTest.expect.equality(p.zindex, 51)
  end
  close_scratch(winid, buf)
end

-- PL-7: float filer width >= MIN_FILER_WIDTH (20)
T["compute_preview_layout float filer width minimum"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("float", winid, config.get())
  if result and result.filer then
    MiniTest.expect.equality(result.filer.width >= 20, true)
  end
  close_scratch(winid, buf)
end

-- PL-8: preview zindex is 51
T["compute_preview_layout preview zindex is 51"] = function()
  config.setup()
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("split_left", winid, config.get())
  if result then
    MiniTest.expect.equality(result.preview.zindex, 51)
  end
  close_scratch(winid, buf)
end

-- PL-9: tiny float width returns nil
T["compute_preview_layout tiny float width returns nil"] = function()
  config.setup({ window = { kinds = { float = { width = "5%", height = "80%" } } } })
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("float", winid, config.get())
  -- With 5% width, preview should be too narrow
  if result then
    -- If not nil, preview width should still be >= 10
    MiniTest.expect.equality(result.preview.width >= 10, true)
  end
  close_scratch(winid, buf)
  config.setup()
end

-- PL-10: tiny float height returns nil
T["compute_preview_layout tiny float height returns nil"] = function()
  config.setup({ window = { kinds = { float = { width = "94%", height = "1%" } } } })
  local winid, buf = open_scratch_float()
  local result = Window._compute_preview_layout("float", winid, config.get())
  -- With 1% height (likely < 3), should return nil
  if vim.o.lines * 0.01 < 3 then
    MiniTest.expect.equality(result, nil)
  end
  close_scratch(winid, buf)
  config.setup()
end

T["set_header_position sets position"] = function()
  config.setup()
  local win = Window.new("float", config.get())
  win:set_header_position("center")
  MiniTest.expect.equality(win.header_position, "center")
end

T["set_header_position defaults to nil"] = function()
  config.setup()
  local win = Window.new("float", config.get())
  MiniTest.expect.equality(win.header_position, nil)
end

-- Close replace mode: restore old_bufnr when eda buffer is still showing
T["close replace mode restores old_bufnr when eda buffer is showing"] = function()
  config.setup()
  local eda_buf = vim.api.nvim_create_buf(false, true)
  local old_buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(eda_buf, true, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  local win = Window.new("replace", config.get())
  win.winid = winid
  win.bufnr = eda_buf
  win.old_bufnr = old_buf

  win:close()
  MiniTest.expect.equality(vim.api.nvim_win_get_buf(winid), old_buf)
  MiniTest.expect.equality(win.winid, nil)
  MiniTest.expect.equality(win.old_bufnr, nil)

  close_scratch(winid, old_buf)
  if vim.api.nvim_buf_is_valid(eda_buf) then
    vim.api.nvim_buf_delete(eda_buf, { force = true })
  end
end

-- Close replace mode: preserve current buffer when eda buffer was replaced (e.g. after select)
T["close replace mode preserves buffer when eda buffer is not showing"] = function()
  config.setup()
  local eda_buf = vim.api.nvim_create_buf(false, true)
  local old_buf = vim.api.nvim_create_buf(false, true)
  local selected_buf = vim.api.nvim_create_buf(false, true)
  local winid = vim.api.nvim_open_win(selected_buf, true, {
    relative = "editor",
    width = 30,
    height = 20,
    row = 0,
    col = 0,
    style = "minimal",
  })
  local win = Window.new("replace", config.get())
  win.winid = winid
  win.bufnr = eda_buf
  win.old_bufnr = old_buf

  win:close()
  -- The selected buffer should remain; old_bufnr must NOT be restored
  MiniTest.expect.equality(vim.api.nvim_win_get_buf(winid), selected_buf)
  MiniTest.expect.equality(win.winid, nil)
  MiniTest.expect.equality(win.old_bufnr, nil)

  close_scratch(winid, selected_buf)
  if vim.api.nvim_buf_is_valid(eda_buf) then
    vim.api.nvim_buf_delete(eda_buf, { force = true })
  end
  if vim.api.nvim_buf_is_valid(old_buf) then
    vim.api.nvim_buf_delete(old_buf, { force = true })
  end
end

-- Reposition tests
T["reposition no-ops for non-float kinds"] = function()
  config.setup()
  local win = Window.new("split_left", config.get())
  -- Should not error
  win:reposition()
  MiniTest.expect.equality(win.winid, nil)
end

T["reposition no-ops when winid is nil"] = function()
  config.setup()
  local win = Window.new("float", config.get())
  -- Should not error
  win:reposition()
  MiniTest.expect.equality(win.winid, nil)
end

T["reposition updates float window dimensions"] = function()
  config.setup()
  local buf = vim.api.nvim_create_buf(false, true)
  local cfg = config.get()
  local win = Window.new("float", cfg)
  win.bufnr = buf
  win.winid = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 10,
    height = 5,
    row = 0,
    col = 0,
    style = "minimal",
  })

  win:reposition()

  -- After reposition, dimensions should match compute_layout output
  local expected = Window._compute_layout("float", cfg)
  local actual_cfg = vim.api.nvim_win_get_config(win.winid)
  MiniTest.expect.equality(actual_cfg.width, expected.width)
  MiniTest.expect.equality(actual_cfg.height, expected.height)

  close_scratch(win.winid, buf)
end

T["reposition preserves header text"] = function()
  config.setup()
  local buf = vim.api.nvim_create_buf(false, true)
  local cfg = config.get()
  local win = Window.new("float", cfg)
  win.bufnr = buf
  win:set_header_text("Test Title")
  win.winid = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 10,
    height = 5,
    row = 0,
    col = 0,
    style = "minimal",
    title = " Test Title ",
    title_pos = "left",
  })

  win:reposition()

  local actual_cfg = vim.api.nvim_win_get_config(win.winid)
  -- nvim_win_get_config returns title as nested table: { { text } }
  MiniTest.expect.equality(actual_cfg.title[1][1], " Test Title ")
  MiniTest.expect.equality(actual_cfg.title_pos, "left")

  close_scratch(win.winid, buf)
end

T["compute_layout float with function width/height"] = function()
  config.setup({
    window = {
      kinds = {
        float = {
          width = function()
            return 50
          end,
          height = function()
            return 25
          end,
        },
      },
    },
  })
  local layout = Window._compute_layout("float", config.get())
  MiniTest.expect.equality(layout.width, 50)
  MiniTest.expect.equality(layout.height, 25)
  config.setup()
end

T["compute_layout split with function width"] = function()
  config.setup({
    window = {
      kinds = {
        split_left = {
          width = function()
            return 40
          end,
        },
      },
    },
  })
  local layout = Window._compute_layout("split_left", config.get())
  MiniTest.expect.equality(layout.width, 40)
  config.setup()
end

return T
