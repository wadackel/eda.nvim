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
  MiniTest.expect.equality(cells, { width = 40, height = 15 })
end

T["fit"]["scales down to the window preserving the aspect ratio"] = function()
  local cells = terminal.fit_cells(
    { width = 4000, height = 3000 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 100, height = 38 })
end

T["fit"]["rounds to the nearest cell so small images keep their aspect ratio"] = function()
  local cells = terminal.fit_cells(
    { width = 200, height = 200 },
    { width = 20.15, height = 41.1 },
    { width = 55, height = 26 }
  )
  MiniTest.expect.equality(cells, { width = 10, height = 5 })
end

T["fit"]["never exceeds the window when rounding up"] = function()
  local cells = terminal.fit_cells(
    { width = 995, height = 100 },
    { width = 10, height = 20 },
    { width = 100, height = 50 }
  )
  MiniTest.expect.equality(cells, { width = 100, height = 5 })
end

T["fit"]["never returns less than one cell"] = function()
  local cells = terminal.fit_cells({ width = 2, height = 2 }, { width = 10, height = 20 }, { width = 100, height = 50 })
  MiniTest.expect.equality(cells, { width = 1, height = 1 })
end

return T
