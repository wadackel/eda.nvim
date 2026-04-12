local Confirm = require("eda.buffer.confirm")
local config = require("eda.config")

local T = MiniTest.new_set()

local root_path = "/project"

-- Default signs from config
local default_signs = { create = "", delete = "", move = "" }

T["show with empty operations calls on_confirm immediately"] = function()
  local confirmed = false
  local cancelled = false
  Confirm.show({}, root_path, function()
    confirmed = true
  end, function()
    cancelled = true
  end)
  MiniTest.expect.equality(confirmed, true)
  MiniTest.expect.equality(cancelled, false)
end

T["show creates float window with correct zindex"] = function()
  local operations = {
    { type = "delete", path = "/project/foo.txt" },
  }

  local win_opened = nil
  Confirm.show(operations, root_path, function() end, function() end)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_confirm" then
      win_opened = win
      break
    end
  end

  MiniTest.expect.no_equality(win_opened, nil)

  local win_config = vim.api.nvim_win_get_config(win_opened)
  MiniTest.expect.equality(win_config.zindex, 52)
  MiniTest.expect.equality(win_config.relative, "editor")

  if vim.api.nvim_win_is_valid(win_opened) then
    vim.api.nvim_win_close(win_opened, true)
  end
end

T["show applies operation highlights"] = function()
  config.setup()
  local operations = {
    { type = "create", path = "/project/new.txt", entry_type = "file" },
    { type = "delete", path = "/project/old.txt" },
    { type = "move", src = "/project/a.txt", dst = "/project/b.txt" },
  }

  local win_opened = nil
  local buf_opened = nil
  Confirm.show(operations, root_path, function() end, function() end)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_confirm" then
      win_opened = win
      buf_opened = buf
      break
    end
  end

  MiniTest.expect.no_equality(buf_opened, nil)

  local ns = vim.api.nvim_get_namespaces()["eda_confirm_hl"]
  local marks = vim.api.nvim_buf_get_extmarks(buf_opened, ns, 0, -1, { details = true })

  -- 3 ops x 2 extmarks (sign + path) each = 6 extmarks (no summary)
  MiniTest.expect.equality(#marks, 6)

  MiniTest.expect.equality(marks[1][4].hl_group, "EdaOpCreateSign")
  MiniTest.expect.equality(marks[2][4].hl_group, "EdaOpCreatePath")
  MiniTest.expect.equality(marks[3][4].hl_group, "EdaOpDeleteSign")
  MiniTest.expect.equality(marks[4][4].hl_group, "EdaOpDeletePath")
  MiniTest.expect.equality(marks[5][4].hl_group, "EdaOpMoveSign")
  MiniTest.expect.equality(marks[6][4].hl_group, "EdaOpMovePath")

  if vim.api.nvim_win_is_valid(win_opened) then
    vim.api.nvim_win_close(win_opened, true)
  end
end

T["y keymap triggers on_confirm callback"] = function()
  local confirmed = false
  local cancelled = false
  local operations = {
    { type = "delete", path = "/project/foo.txt" },
  }

  Confirm.show(operations, root_path, function()
    confirmed = true
  end, function()
    cancelled = true
  end)

  vim.api.nvim_feedkeys("y", "x", false)

  MiniTest.expect.equality(confirmed, true)
  MiniTest.expect.equality(cancelled, false)
end

T["Esc keymap triggers on_cancel callback"] = function()
  local confirmed = false
  local cancelled = false
  local operations = {
    { type = "delete", path = "/project/foo.txt" },
  }

  Confirm.show(operations, root_path, function()
    confirmed = true
  end, function()
    cancelled = true
  end)

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  MiniTest.expect.equality(confirmed, false)
  MiniTest.expect.equality(cancelled, true)
end

T["show buffer contains operation lines without summary"] = function()
  config.setup()
  local operations = {
    { type = "create", path = "/project/new.txt", entry_type = "file" },
    { type = "delete", path = "/project/old.txt" },
  }

  local win_opened = nil
  local buf_opened = nil
  Confirm.show(operations, root_path, function() end, function() end)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_confirm" then
      win_opened = win
      buf_opened = buf
      break
    end
  end

  MiniTest.expect.no_equality(buf_opened, nil)

  local lines = vim.api.nvim_buf_get_lines(buf_opened, 0, -1, false)
  -- 2 ops + 2 padding lines (top + bottom)
  MiniTest.expect.equality(#lines, 4)
  MiniTest.expect.equality(lines[1], "")
  MiniTest.expect.equality(lines[2]:find("new.txt") ~= nil, true)
  MiniTest.expect.equality(lines[3]:find("old.txt") ~= nil, true)
  MiniTest.expect.equality(lines[4], "")

  if vim.api.nvim_win_is_valid(win_opened) then
    vim.api.nvim_win_close(win_opened, true)
  end
end

T["show sets window highlights"] = function()
  local operations = {
    { type = "delete", path = "/project/foo.txt" },
  }

  local win_opened = nil
  Confirm.show(operations, root_path, function() end, function() end)

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_confirm" then
      win_opened = win
      break
    end
  end

  MiniTest.expect.no_equality(win_opened, nil)

  local winhl = vim.wo[win_opened].winhl
  MiniTest.expect.equality(winhl:find("FloatBorder:EdaConfirmBorder") ~= nil, true)
  MiniTest.expect.equality(winhl:find("FloatTitle:EdaConfirmTitle") ~= nil, true)
  MiniTest.expect.equality(winhl:find("FloatFooter:EdaConfirmFooter") ~= nil, true)

  if vim.api.nvim_win_is_valid(win_opened) then
    vim.api.nvim_win_close(win_opened, true)
  end
end

T["format_path"] = MiniTest.new_set()

T["format_path"]["full returns absolute path"] = function()
  local result = Confirm._format_path("/project/src/foo.lua", "/project", "full")
  MiniTest.expect.equality(result, "/project/src/foo.lua")
end

T["format_path"]["short returns root-relative path"] = function()
  local result = Confirm._format_path("/project/src/foo.lua", "/project", "short")
  MiniTest.expect.equality(result, "src/foo.lua")
end

T["format_path"]["short with path outside root returns original"] = function()
  local result = Confirm._format_path("/other/foo.lua", "/project", "short")
  MiniTest.expect.equality(result, "/other/foo.lua")
end

T["format_path"]["minimal shortens intermediate dirs"] = function()
  local result = Confirm._format_path("/project/src/core/build_steps/foo.lua", "/project", "minimal")
  MiniTest.expect.equality(result, "s/c/b/foo.lua")
end

T["format_path"]["minimal with single file"] = function()
  local result = Confirm._format_path("/project/foo.lua", "/project", "minimal")
  MiniTest.expect.equality(result, "foo.lua")
end

T["format_path"]["function format calls user function"] = function()
  local fmt = function(path, rp)
    return "[" .. path:sub(#rp + 2) .. "]"
  end
  local result = Confirm._format_path("/project/src/foo.lua", "/project", fmt)
  MiniTest.expect.equality(result, "[src/foo.lua]")
end

T["format_operations"] = MiniTest.new_set()

T["format_operations"]["uses configured sign icons"] = function()
  local ops = {
    { type = "create", path = "/project/src/new.txt", entry_type = "file" },
    { type = "delete", path = "/project/src/old.txt" },
    { type = "move", src = "/project/src/a.txt", dst = "/project/src/b.txt" },
  }
  local result = Confirm._format_operations(ops, "/project", "short", default_signs)
  MiniTest.expect.equality(result.lines[2], "    src/new.txt  (file)")
  MiniTest.expect.equality(result.lines[3], "    src/old.txt")
  MiniTest.expect.equality(result.lines[4], "    src/a.txt → .../b.txt")
end

T["format_operations"]["full format uses absolute paths"] = function()
  local ops = {
    { type = "delete", path = "/project/foo.txt" },
  }
  local result = Confirm._format_operations(ops, "/project", "full", default_signs)
  MiniTest.expect.equality(result.lines[2], "    /project/foo.txt")
end

T["format_operations"]["move without common prefix shows full dst"] = function()
  local ops = {
    { type = "move", src = "/project/src/foo.lua", dst = "/project/lib/foo.lua" },
  }
  local result = Confirm._format_operations(ops, "/project", "short", default_signs)
  MiniTest.expect.equality(result.lines[2], "    src/foo.lua → lib/foo.lua")
end

T["format_operations"]["returns segments with correct highlight groups"] = function()
  local ops = {
    { type = "create", path = "/project/new.txt", entry_type = "file" },
    { type = "delete", path = "/project/old.txt" },
  }
  local result = Confirm._format_operations(ops, "/project", "short", default_signs)
  MiniTest.expect.equality(#result.segments, 2)
  MiniTest.expect.equality(result.segments[1].sign_hl, "EdaOpCreateSign")
  MiniTest.expect.equality(result.segments[1].path_hl, "EdaOpCreatePath")
  MiniTest.expect.equality(result.segments[2].sign_hl, "EdaOpDeleteSign")
  MiniTest.expect.equality(result.segments[2].path_hl, "EdaOpDeletePath")
end

T["format_operations"]["returns counts instead of summary lines"] = function()
  local ops = {
    { type = "create", path = "/project/a.txt", entry_type = "file" },
    { type = "create", path = "/project/b.txt", entry_type = "file" },
    { type = "delete", path = "/project/c.txt" },
    { type = "move", src = "/project/d.txt", dst = "/project/e.txt" },
  }
  local result = Confirm._format_operations(ops, "/project", "short", default_signs)
  MiniTest.expect.equality(#result.lines, 6)
  MiniTest.expect.equality(result.counts.create, 2)
  MiniTest.expect.equality(result.counts.delete, 1)
  MiniTest.expect.equality(result.counts.move, 1)
end

T["format_operations"]["counts reflect zero-count types"] = function()
  local ops = {
    { type = "delete", path = "/project/a.txt" },
    { type = "delete", path = "/project/b.txt" },
  }
  local result = Confirm._format_operations(ops, "/project", "short", default_signs)
  MiniTest.expect.equality(result.counts.delete, 2)
  MiniTest.expect.equality(result.counts.create, 0)
  MiniTest.expect.equality(result.counts.move, 0)
end

T["format_operations"]["custom signs are used in output"] = function()
  local ops = {
    { type = "create", path = "/project/new.txt", entry_type = "file" },
    { type = "delete", path = "/project/old.txt" },
    { type = "move", src = "/project/a.txt", dst = "/project/b.txt" },
  }
  local custom_signs = { create = "+", delete = "-", move = "~" }
  local result = Confirm._format_operations(ops, "/project", "short", custom_signs)
  MiniTest.expect.equality(result.lines[2], "  +  new.txt  (file)")
  MiniTest.expect.equality(result.lines[3], "  -  old.txt")
  MiniTest.expect.equality(result.lines[4], "  ~  a.txt → b.txt")
end

T["build_title_chunks"] = MiniTest.new_set()

T["build_title_chunks"]["includes all non-zero counts"] = function()
  local counts = { delete = 2, create = 1, move = 3 }
  local chunks = Confirm._build_title_chunks(counts, default_signs)
  MiniTest.expect.equality(#chunks, 10)
  MiniTest.expect.equality(chunks[1][1], " Confirm: ")
  MiniTest.expect.equality(chunks[1][2], "EdaConfirmTitle")
  MiniTest.expect.equality(chunks[2][1], "")
  MiniTest.expect.equality(chunks[2][2], "EdaOpDeleteSign")
  MiniTest.expect.equality(chunks[3][1], " 2")
  MiniTest.expect.equality(chunks[3][2], "EdaOpDeleteText")
end

T["build_title_chunks"]["omits zero-count types"] = function()
  local counts = { delete = 0, create = 3, move = 0 }
  local chunks = Confirm._build_title_chunks(counts, default_signs)
  MiniTest.expect.equality(#chunks, 4)
  MiniTest.expect.equality(chunks[2][1], "")
  MiniTest.expect.equality(chunks[2][2], "EdaOpCreateSign")
  MiniTest.expect.equality(chunks[3][1], " 3")
  MiniTest.expect.equality(chunks[3][2], "EdaOpCreateText")
end

T["build_title_chunks"]["uses correct highlight groups for each type"] = function()
  local counts = { delete = 1, create = 0, move = 1 }
  local chunks = Confirm._build_title_chunks(counts, default_signs)
  MiniTest.expect.equality(#chunks, 7)
  MiniTest.expect.equality(chunks[2][2], "EdaOpDeleteSign")
  MiniTest.expect.equality(chunks[5][2], "EdaOpMoveSign")
end

T["abbreviate_dst"] = MiniTest.new_set()

T["abbreviate_dst"]["same directory rename"] = function()
  local result = Confirm._abbreviate_dst("src/core/foo.lua", "src/core/bar.lua")
  MiniTest.expect.equality(result, ".../bar.lua")
end

T["abbreviate_dst"]["cross directory move"] = function()
  local result = Confirm._abbreviate_dst("src/a/foo.lua", "src/b/foo.lua")
  MiniTest.expect.equality(result, ".../b/foo.lua")
end

T["abbreviate_dst"]["no common prefix"] = function()
  local result = Confirm._abbreviate_dst("src/foo.lua", "lib/foo.lua")
  MiniTest.expect.equality(result, "lib/foo.lua")
end

T["abbreviate_dst"]["single file no dirs"] = function()
  local result = Confirm._abbreviate_dst("foo.lua", "bar.lua")
  MiniTest.expect.equality(result, "bar.lua")
end

return T
