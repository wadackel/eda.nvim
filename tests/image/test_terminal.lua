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

T["fit"]["keeps natural size when the image fits"] = function()
  local cells = terminal.fit_cells(
    { width = 400, height = 300 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 40, height = 15, axis = "width" })
end

T["fit"]["scales down to the window preserving the aspect ratio"] = function()
  local cells = terminal.fit_cells(
    { width = 4000, height = 3000 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 100, height = 38, axis = "width" })
end

T["fit"]["rounds to the nearest cell so small images keep their aspect ratio"] = function()
  local cells = terminal.fit_cells(
    { width = 200, height = 200 },
    { width = 20.15, height = 41.1 },
    { width = 55, height = 26 }
  )
  MiniTest.expect.equality(cells, { width = 10, height = 5, axis = "width" })
end

T["fit"]["reports the height as the binding axis for tall images"] = function()
  local cells = terminal.fit_cells(
    { width = 300, height = 4000 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 8, height = 50, axis = "height" })
end

T["fit"]["never exceeds the window when rounding up"] = function()
  local cells = terminal.fit_cells(
    { width = 995, height = 100 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 100, height = 5, axis = "width" })
end

T["fit"]["never returns less than one cell"] = function()
  local cells = terminal.fit_cells({ width = 2, height = 2 }, { width = 10, height = 20 }, { width = 100, height = 50 })
  MiniTest.expect.equality(cells, { width = 1, height = 1, axis = "width" })
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

T["detect"] = MiniTest.new_set()

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

T["autocmds"] = MiniTest.new_set()

T["autocmds"]["VimResized handler is registered on first cell_size call, not on require"] = function()
  terminal._reset()
  MiniTest.expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "eda_image_terminal" }), false)
  terminal.cell_size()
  local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "eda_image_terminal" })
  MiniTest.expect.equality(ok and #autocmds > 0, true)
end

return T
