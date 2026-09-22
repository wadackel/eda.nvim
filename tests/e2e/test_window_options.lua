local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

local function set_user_options()
  e2e.exec(child, [[vim.cmd("set foldmethod=indent spell list colorcolumn=80")]])
end

local function expand_all()
  e2e.feed(child, "gE")
  e2e.wait_until(
    child,
    [[
    for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find("deep.txt") then return true end
    end
    return false
  ]]
  )
end

local function expect_explorer_window_clean()
  local state = e2e.exec(
    child,
    [[
    local folded = 0
    for i = 1, vim.api.nvim_buf_line_count(0) do
      if vim.fn.foldclosed(i) ~= -1 then
        folded = folded + 1
      end
    end
    return {
      filetype = vim.bo.filetype,
      folded = folded,
      spell = vim.wo.spell,
      list = vim.wo.list,
      colorcolumn = vim.wo.colorcolumn,
    }
  ]]
  )
  MiniTest.expect.equality(state, { filetype = "eda", folded = 0, spell = false, list = false, colorcolumn = "" })
end

T["window options"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_dir(tmp .. "/sub/inner")
      e2e.create_file(tmp .. "/sub/a.txt", "a")
      e2e.create_file(tmp .. "/sub/inner/deep.txt", "deep")
      e2e.create_file(tmp .. "/indented.txt", "top\n  nested one\n  nested two\n    deeper\n")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

for _, kind in ipairs({ "split_left", "replace" }) do
  T["window options"][kind .. " explorer ignores the user's folds and spell"] = function()
    set_user_options()
    e2e.setup_eda(child, string.format([[{ window = { kind = %q } }]], kind))
    e2e.open_eda(child, tmp)
    expand_all()
    expect_explorer_window_clean()
  end
end

T["window options"]["preview float ignores the user's folds"] = function()
  set_user_options()
  e2e.setup_eda(child, [[{ preview = { enabled = true, debounce = 0 } }]])
  e2e.open_eda(child, tmp)

  e2e.wait_until(
    child,
    [[
    for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if l:find("indented.txt") then
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        return true
      end
    end
    return false
  ]]
  )
  e2e.wait_until(
    child,
    [[
    local winid = require("eda").get_current().preview.winid
    if not (winid and vim.api.nvim_win_is_valid(winid)) then return false end
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false)
    return lines[2] == "  nested one"
  ]]
  )

  MiniTest.expect.equality(
    e2e.exec(child, [[return vim.wo[require("eda").get_current().preview.winid].foldenable]]),
    false
  )
end

return T
