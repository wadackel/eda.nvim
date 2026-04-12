local config = require("eda.config")

local T = MiniTest.new_set()

T["setup"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup()
    end,
  },
})

T["setup"]["returns defaults when no opts"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(c.show_hidden, true)
  MiniTest.expect.equality(c.window.kind, "float")
  MiniTest.expect.equality(c.window.buf_opts.filetype, "eda")
  MiniTest.expect.equality(c.expand_depth, 5)
end

T["setup"]["merges user opts"] = function()
  config.setup({ show_hidden = true })
  local c = config.get()
  MiniTest.expect.equality(c.show_hidden, true)
  -- unrelated fields unchanged
  MiniTest.expect.equality(c.window.kind, "float")
end

T["setup"]["deep merges nested tables"] = function()
  config.setup({ window = { kind = "float" } })
  local c = config.get()
  MiniTest.expect.equality(c.window.kind, "float")
  -- other nested values preserved
  MiniTest.expect.equality(c.window.border, "rounded")
end

T["setup"]["overrides mappings"] = function()
  config.setup({ mappings = { ["<CR>"] = "close" } })
  local c = config.get()
  MiniTest.expect.equality(c.mappings["<CR>"], "close")
end

T["setup"]["header defaults to short format"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(type(c.header), "table")
  MiniTest.expect.equality(c.header.format, "short")
end

T["setup"]["header can be disabled with false"] = function()
  config.setup({ header = false })
  local c = config.get()
  MiniTest.expect.equality(c.header, false)
end

T["setup"]["header format can be overridden"] = function()
  config.setup({ header = { format = "full" } })
  local c = config.get()
  MiniTest.expect.equality(c.header.format, "full")
end

T["setup"]["header position defaults to left"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(c.header.position, "left")
end

T["setup"]["header position can be overridden to center"] = function()
  config.setup({ header = { position = "center" } })
  local c = config.get()
  MiniTest.expect.equality(c.header.position, "center")
end

T["setup"]["header position can be overridden to right"] = function()
  config.setup({ header = { position = "right" } })
  local c = config.get()
  MiniTest.expect.equality(c.header.position, "right")
end

T["setup"]["header false does not error with position"] = function()
  config.setup({ header = false })
  local c = config.get()
  MiniTest.expect.equality(c.header, false)
end

T["setup"]["default toggle_hidden mapping is g."] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(c.mappings["g."], "toggle_hidden")
  MiniTest.expect.equality(c.mappings["gh"], nil)
end

T["setup"]["default_mappings false clears default mappings"] = function()
  config.setup({ default_mappings = false })
  local c = config.get()
  MiniTest.expect.equality(c.mappings, {})
end

T["setup"]["default_mappings false with explicit mappings keeps only those"] = function()
  config.setup({ default_mappings = false, mappings = { ["<CR>"] = "select", ["q"] = "close" } })
  local c = config.get()
  MiniTest.expect.equality(c.mappings["<CR>"], "select")
  MiniTest.expect.equality(c.mappings["q"], "close")
  MiniTest.expect.equality(c.mappings["<C-t>"], nil)
end

T["setup"]["omitting default_mappings preserves defaults"] = function()
  config.setup({ mappings = { ["<CR>"] = "close" } })
  local c = config.get()
  MiniTest.expect.equality(c.mappings["<CR>"], "close")
  MiniTest.expect.equality(c.mappings["q"], "close")
end

T["setup"]["confirm true normalizes to default table"] = function()
  config.setup({ confirm = true })
  local c = config.get()
  MiniTest.expect.equality(c.confirm.delete, true)
  MiniTest.expect.equality(c.confirm.move, "overwrite_only")
  MiniTest.expect.equality(c.confirm.create, false)
end

T["setup"]["confirm false normalizes to all false"] = function()
  config.setup({ confirm = false })
  local c = config.get()
  MiniTest.expect.equality(c.confirm.delete, false)
  MiniTest.expect.equality(c.confirm.move, false)
  MiniTest.expect.equality(c.confirm.create, false)
end

T["setup"]["confirm table merges with defaults"] = function()
  config.setup({ confirm = { delete = false } })
  local c = config.get()
  MiniTest.expect.equality(c.confirm.delete, false)
  MiniTest.expect.equality(c.confirm.move, "overwrite_only")
  MiniTest.expect.equality(c.confirm.create, false)
end

T["setup"]["confirm table with all fields"] = function()
  config.setup({ confirm = { delete = true, move = true, create = 5 } })
  local c = config.get()
  MiniTest.expect.equality(c.confirm.delete, true)
  MiniTest.expect.equality(c.confirm.move, true)
  MiniTest.expect.equality(c.confirm.create, 5)
end

T["setup"]["confirm create=0 normalizes to false"] = function()
  config.setup({ confirm = { create = 0 } })
  local c = config.get()
  MiniTest.expect.equality(c.confirm.create, false)
end

T["setup"]["default confirm matches true behavior"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(c.confirm.delete, true)
  MiniTest.expect.equality(c.confirm.move, "overwrite_only")
  MiniTest.expect.equality(c.confirm.create, false)
end

T["normalize_confirm"] = MiniTest.new_set()

T["normalize_confirm"]["true returns defaults"] = function()
  local result = config._normalize_confirm(true)
  MiniTest.expect.equality(result, {
    delete = true,
    move = "overwrite_only",
    create = false,
    path_format = "short",
    signs = { create = "", delete = "", move = "" },
  })
end

T["normalize_confirm"]["false returns all false"] = function()
  local result = config._normalize_confirm(false)
  MiniTest.expect.equality(result, {
    delete = false,
    move = false,
    create = false,
    path_format = "short",
    signs = { create = "", delete = "", move = "" },
  })
end

T["normalize_confirm"]["nil returns defaults"] = function()
  local result = config._normalize_confirm(nil)
  MiniTest.expect.equality(result, {
    delete = true,
    move = "overwrite_only",
    create = false,
    path_format = "short",
    signs = { create = "", delete = "", move = "" },
  })
end

T["normalize_confirm"]["partial table merges with defaults"] = function()
  local result = config._normalize_confirm({ move = false })
  MiniTest.expect.equality(result, {
    delete = true,
    move = false,
    create = false,
    path_format = "short",
    signs = { create = "", delete = "", move = "" },
  })
end

T["normalize_confirm"]["create 0 becomes false"] = function()
  local result = config._normalize_confirm({ create = 0 })
  MiniTest.expect.equality(result, {
    delete = true,
    move = "overwrite_only",
    create = false,
    path_format = "short",
    signs = { create = "", delete = "", move = "" },
  })
end

T["get"] = MiniTest.new_set()

T["get"]["returns config table"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(type(c), "table")
  MiniTest.expect.equality(type(c.root_markers), "table")
end

return T
