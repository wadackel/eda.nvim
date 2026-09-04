local terminal = require("eda.image.terminal")

local T = MiniTest.new_set()

T["passthrough"] = MiniTest.new_set()

T["passthrough"]["wraps data in a tmux DCS and doubles ESC"] = function()
  MiniTest.expect.equality(terminal.tmux_wrap("\27_Ga=p\27\\"), "\27Ptmux;\27\27_Ga=p\27\27\\\27\\")
end

T["offset"] = MiniTest.new_set()

T["offset"]["adds a top status line to pane_top"] = function()
  MiniTest.expect.equality(terminal.parse_tmux_offset("0 96 top 55 54"), { 1, 96 })
end

T["offset"]["ignores a bottom status line"] = function()
  MiniTest.expect.equality(terminal.parse_tmux_offset("3 0 bottom 55 54"), { 3, 0 })
end

T["offset"]["never returns a negative offset"] = function()
  MiniTest.expect.equality(terminal.parse_tmux_offset("-2 -5 bottom 55 54"), { 0, 0 })
end

T["offset"]["falls back to zero on unexpected output"] = function()
  MiniTest.expect.equality(terminal.parse_tmux_offset("no server running"), { 0, 0 })
end

T["border_size"] = MiniTest.new_set()

T["border_size"]["named borders occupy one cell"] = function()
  MiniTest.expect.equality(terminal.border_size("rounded"), { top = 1, left = 1 })
  MiniTest.expect.equality(terminal.border_size("single"), { top = 1, left = 1 })
end

T["border_size"]["none and shadow occupy nothing at the top-left"] = function()
  MiniTest.expect.equality(terminal.border_size("none"), { top = 0, left = 0 })
  MiniTest.expect.equality(terminal.border_size("shadow"), { top = 0, left = 0 })
  MiniTest.expect.equality(terminal.border_size(nil), { top = 0, left = 0 })
end

T["border_size"]["array borders check the top and left edge characters"] = function()
  MiniTest.expect.equality(terminal.border_size({ "", "", "", "|", "", "", "", "|" }), { top = 0, left = 1 })
  MiniTest.expect.equality(
    terminal.border_size({ "+", { "-", "Hl" }, "+", "", "+", "-", "+", "" }),
    { top = 1, left = 0 }
  )
end

T["fit"] = MiniTest.new_set()

local function size(w, h)
  return { width = w, height = h }
end

local function crop(x, y, w, h)
  return { x = x, y = y, width = w, height = h }
end

-- image, cell, window -> expected fit
local fit_cases = {
  ["keeps natural size when the image fits"] = {
    size(400, 300),
    size(10, 20),
    size(100, 50),
    { width = 40, height = 15, crop = crop(0, 0, 400, 300) },
  },
  ["scales down to the window and crops the aspect remainder"] = {
    size(4000, 3000),
    size(10, 20),
    size(100, 50),
    { width = 100, height = 38, crop = crop(26, 0, 3947, 3000) },
  },
  ["sends both axes for the WezTerm overflow case"] = {
    size(2048, 1546),
    size(15, 31),
    size(121, 42),
    { width = 115, height = 42, crop = crop(0, 0, 2048, 1546) },
  },
  ["rounds to whole cells even when the cell size is fractional"] = {
    size(200, 200),
    size(20.15, 41.1),
    size(55, 26),
    { width = 10, height = 5, crop = crop(2, 0, 196, 200) },
  },
  ["fills the window for tall images and crops rather than shrinking"] = {
    size(300, 4000),
    size(10, 20),
    size(100, 50),
    { width = 8, height = 50, crop = crop(0, 125, 300, 3750) },
  },
  ["keeps a banner at full width instead of collapsing it to one row"] = {
    size(3278, 289),
    size(15, 31),
    size(46, 22),
    { width = 46, height = 2, crop = crop(31, 0, 3216, 289) },
  },
  ["never exceeds the window when rounding up"] = {
    size(995, 100),
    size(10, 20),
    size(100, 50),
    { width = 100, height = 5, crop = crop(0, 0, 995, 100) },
  },
  ["upscales a sub-cell icon to a whole cell"] = {
    size(16, 16),
    size(15, 31),
    size(100, 50),
    { width = 2, height = 1, crop = crop(0, 0, 15, 16) },
  },
  ["never returns less than one cell"] = {
    size(2, 2),
    size(10, 20),
    size(100, 50),
    { width = 2, height = 1, crop = crop(0, 0, 2, 2) },
  },
}

for name, case in pairs(fit_cases) do
  T["fit"][name] = function()
    local image, cell, window, expected = unpack(case)
    local fit = terminal.fit_cells(image, cell, window)
    MiniTest.expect.equality(fit, expected)
    for _, n in ipairs({ fit.width, fit.height, fit.crop.x, fit.crop.y, fit.crop.width, fit.crop.height }) do
      MiniTest.expect.equality(n % 1, 0)
    end
    MiniTest.expect.equality(fit.width <= window.width and fit.height <= window.height, true)
    MiniTest.expect.equality(fit.crop.x + fit.crop.width <= image.width, true)
    MiniTest.expect.equality(fit.crop.y + fit.crop.height <= image.height, true)
  end
end

T["is_tmux"] = MiniTest.new_set()

T["is_tmux"]["is false without a UI even when TMUX is inherited"] = function()
  local saved_tmux, saved_pane = vim.env.TMUX, vim.env.TMUX_PANE
  terminal._reset()
  vim.env.TMUX = "/tmp/tmux-1/default,1,0"
  vim.env.TMUX_PANE = "%0"
  MiniTest.expect.equality(#vim.api.nvim_list_uis(), 0)
  MiniTest.expect.equality(terminal.is_tmux(), false)
  vim.env.TMUX, vim.env.TMUX_PANE = saved_tmux, saved_pane
  terminal._reset()
end

T["write"] = MiniTest.new_set()

T["write"]["falls back to io.write and flushes when nvim_ui_send is unavailable"] = function()
  local saved_send, saved_write, saved_flush, saved_writer = vim.api.nvim_ui_send, io.write, io.flush, terminal.writer
  local saved_tmux = terminal.is_tmux
  local written, flushed = nil, false
  vim.api.nvim_ui_send = nil
  io.write = function(data)
    written = data
  end
  io.flush = function()
    flushed = true
  end
  terminal.writer = nil
  terminal.is_tmux = function()
    return false
  end
  terminal.write("\27_Gq=2\27\\")
  vim.api.nvim_ui_send, io.write, io.flush, terminal.writer = saved_send, saved_write, saved_flush, saved_writer
  terminal.is_tmux = saved_tmux
  MiniTest.expect.equality(written, "\27_Gq=2\27\\")
  MiniTest.expect.equality(flushed, true)
end

local detect_restore

T["detect"] = MiniTest.new_set({
  hooks = {
    post_case = function()
      if detect_restore then
        detect_restore()
        detect_restore = nil
      end
    end,
  },
})

T["detect"]["enables tmux passthrough before querying the terminal"] = function()
  terminal._reset()
  local saved =
    { uis = vim.api.nvim_list_uis, system = vim.fn.system, is_tmux = terminal.is_tmux, writer = terminal.writer }
  local order = {}
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  vim.fn.system = function(cmd)
    order[#order + 1] = table.concat(cmd, " ")
    return ""
  end
  terminal.is_tmux = function()
    return true
  end
  terminal.writer = function(data)
    order[#order + 1] = data
  end
  terminal.detect(function() end)
  vim.api.nvim_list_uis, vim.fn.system, terminal.is_tmux, terminal.writer =
    saved.uis, saved.system, saved.is_tmux, saved.writer
  terminal._reset()
  MiniTest.expect.equality(order[1], "tmux set -p allow-passthrough all")
  MiniTest.expect.equality(order[2] ~= nil and order[2]:find("\27[>q", 1, true) ~= nil, true)
end

local function stub_detect_env(opts)
  local saved = {
    uis = vim.api.nvim_list_uis,
    system = vim.fn.system,
    is_tmux = terminal.is_tmux,
    writer = terminal.writer,
    env_hint = terminal.env_hint,
    timeout = terminal.detect_timeout_ms,
  }
  terminal._reset()
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  vim.fn.system = function()
    return ""
  end
  terminal.is_tmux = function()
    return opts.tmux == true
  end
  terminal.env_hint = function()
    return opts.hint
  end
  terminal.detect_timeout_ms = opts.timeout or 1000
  local writes = {}
  terminal.writer = function(data)
    writes[#writes + 1] = data
  end
  detect_restore = function()
    vim.api.nvim_list_uis = saved.uis
    vim.fn.system = saved.system
    terminal.is_tmux = saved.is_tmux
    terminal.writer = saved.writer
    terminal.env_hint = saved.env_hint
    terminal.detect_timeout_ms = saved.timeout
    terminal._reset()
  end
  return writes, detect_restore
end

local function respond(sequence)
  vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = sequence } })
end

local KITTY_OK = "\27_Gi=31;OK\27\\"

T["detect"]["probes the terminal with XTVERSION and the graphics query in one write outside tmux"] = function()
  local writes, restore = stub_detect_env({ tmux = false, hint = nil })
  terminal.detect(function() end)
  restore()
  MiniTest.expect.equality(#writes, 1)
  MiniTest.expect.equality(writes[1]:find("\27[>q", 1, true) ~= nil, true)
  MiniTest.expect.equality(writes[1]:find("\27_G", 1, true) ~= nil, true)
  MiniTest.expect.equality(writes[1]:find("a=q", 1, true) ~= nil, true)
  MiniTest.expect.equality(writes[1]:find("i=31", 1, true) ~= nil, true)
end

T["detect"]["a graphics query OK marks the terminal supported for the session"] = function()
  local _, restore = stub_detect_env({ tmux = false, hint = nil })
  local results = {}
  terminal.detect(function(term)
    results[#results + 1] = term
  end)
  respond(KITTY_OK)
  vim.wait(200, function()
    return #results == 1
  end, 10)
  terminal.detect(function(term)
    results[#results + 1] = term
  end)
  restore()
  MiniTest.expect.equality(results[1], { supported = true, name = "kitty-graphics" })
  MiniTest.expect.equality(results[2], { supported = true, name = "kitty-graphics" })
end

T["detect"]["an unknown XTVERSION name waits for the graphics query; a known name settles immediately"] = function()
  local _, restore = stub_detect_env({ tmux = true, hint = nil })
  local results = {}
  terminal.detect(function(term)
    results[#results + 1] = term
  end)
  respond("\27P>|limenty 1.0\27\\")
  vim.wait(100, function()
    return #results == 1
  end, 10)
  MiniTest.expect.equality(#results, 0)
  respond(KITTY_OK)
  vim.wait(200, function()
    return #results == 1
  end, 10)
  MiniTest.expect.equality(results[1], { supported = true, name = "limenty" })
  restore()

  local _, restore2 = stub_detect_env({ tmux = true, hint = nil })
  local known = {}
  terminal.detect(function(term)
    known[#known + 1] = term
  end)
  respond("\27P>|kitty 0.48.2\27\\")
  vim.wait(200, function()
    return #known == 1
  end, 10)
  restore2()
  MiniTest.expect.equality(known[1], { supported = true, name = "kitty" })
end

T["detect"]["falls back to the environment hint when nothing answers"] = function()
  local _, restore = stub_detect_env({ tmux = false, hint = nil, timeout = 50 })
  local results = {}
  terminal.detect(function(term)
    results[#results + 1] = term
  end)
  vim.wait(1000, function()
    return #results == 1
  end, 10)
  restore()
  MiniTest.expect.equality(results[1], { supported = false, name = "unknown" })

  local _, restore2 = stub_detect_env({ tmux = true, hint = "wezterm", timeout = 50 })
  local hinted = {}
  terminal.detect(function(term)
    hinted[#hinted + 1] = term
  end)
  vim.wait(1000, function()
    return #hinted == 1
  end, 10)
  restore2()
  MiniTest.expect.equality(hinted[1], { supported = true, name = "wezterm" })
end

T["autocmds"] = MiniTest.new_set()

T["autocmds"]["VimResized handler is registered on first cell_size call, not on require"] = function()
  terminal._reset()
  MiniTest.expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "eda_image_terminal" }), false)
  terminal.cell_size()
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "eda_image_terminal" })
  MiniTest.expect.equality(ok and #autocmds > 0, true)
end

return T
