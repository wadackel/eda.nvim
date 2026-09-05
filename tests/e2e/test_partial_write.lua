local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      e2e.exec(child, [[require("eda.config").get().delete_to_trash = false]])
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/a", "A")
      e2e.create_file(tmp .. "/b", "B")
      e2e.create_file(tmp .. "/keep", "KEEP")
      e2e.open_eda(child, tmp)
      e2e.exec(
        child,
        [[
        _G.results = {}
        vim.api.nvim_create_autocmd("User", {
          pattern = "EdaMutationPost",
          callback = function(args) table.insert(_G.results, args.data.results) end,
        })
      ]]
      )
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

local function cursor_on(name)
  e2e.wait_until(
    child,
    string.format(
      [[
    for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      if line == %q then vim.api.nvim_win_set_cursor(0, { i, 0 }); return true end
    end
    return false
  ]],
      name
    )
  )
end

local function rename(from, to)
  cursor_on(from)
  e2e.feed(child, "cc")
  e2e.feed_insert(child, to)
end

local function fail_second(operation)
  e2e.exec(
    child,
    string.format(
      [[
    local Fs = require("eda.fs")
    local original = Fs[%q]
    _G.calls = 0
    Fs[%q] = function(...)
      _G.calls = _G.calls + 1
      local args = { ... }
      if _G.calls == 2 then
        vim.schedule(function() args[#args]("injected failure") end)
      else
        original(unpack(args))
      end
    end
  ]],
      operation,
      operation
    )
  )
end

local function partial_then_retry()
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "#_G.results == 1 and vim.bo.modifiable")
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)
  MiniTest.expect.equality(e2e.exec(child, "return #_G.results[1].completed"), 1)
  MiniTest.expect.equality(e2e.exec(child, "return _G.results[1].error"), "injected failure")
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "#_G.results == 2 and not vim.bo.modified")
  MiniTest.expect.equality(e2e.exec(child, "return #_G.results[2].completed"), 1)
  MiniTest.expect.equality(e2e.exec(child, "return _G.calls"), 3)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
end

T["retries only the pending move after a partial failure"] = function()
  rename("a", "new_a")
  rename("b", "new_b")
  fail_second("move")
  partial_then_retry()
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_b"), { "B" })
end

T["assigns completed creates IDs before retrying pending creates"] = function()
  e2e.feed(child, "Go")
  e2e.feed_insert(child, "created_a\ncreated_b")
  fail_second("create")
  partial_then_retry()
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/created_a"), 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/created_b"), 1)
end

T["does not delete a replacement for an already completed deletion"] = function()
  cursor_on("a")
  e2e.feed(child, "dd")
  cursor_on("b")
  e2e.feed(child, "dd")
  fail_second("delete")
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "#_G.results == 1 and vim.bo.modifiable")
  local completed = e2e.exec(child, "return _G.results[1].completed[1].path")
  e2e.create_file(completed, "replacement")
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "#_G.results == 2 and not vim.bo.modified")
  MiniTest.expect.equality(e2e.exec(child, "return _G.calls"), 3)
  MiniTest.expect.equality(vim.fn.readfile(completed), { "replacement" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
end

T["rejects another write while execution is still pending"] = function()
  rename("a", "new_a")
  e2e.exec(
    child,
    [[
    local Fs = require("eda.fs")
    local execute = Fs.execute_operations
    _G.execute_calls = 0
    Fs.execute_operations = function(ops, opts, callback)
      _G.execute_calls = _G.execute_calls + 1
      _G.release_write = function() execute(ops, opts, callback) end
    end
  ]]
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "_G.release_write ~= nil")
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modifiable"), false)
  e2e.exec(child, [[require("eda")._handle_write(require("eda").get_current())]])
  MiniTest.expect.equality(e2e.exec(child, "return _G.execute_calls"), 1)
  e2e.exec(child, "_G.release_write()")
  e2e.wait_until(child, "not vim.bo.modified and vim.bo.modifiable")
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_a"), { "A" })
end

for _, event in ipairs({ "EdaMutationPre", "EdaMutationPost" }) do
  T["does not leave the buffer locked after an error in " .. event] = function()
    rename("a", "new_a")
    e2e.exec(
      child,
      string.format(
        [[
      vim.api.nvim_create_autocmd("User", {
        pattern = %q,
        once = true,
        callback = function() error("injected hook failure") end,
      })
    ]],
        event
      )
    )
    e2e.feed(child, ":w<CR>")
    e2e.wait_until(child, "#_G.results == 1 and not vim.bo.modified and vim.bo.modifiable")
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_a"), { "A" })
  end
end

T["retains relocated descendants when a later independent move fails"] = function()
  e2e.create_file(tmp .. "/src/inside", "inside")
  e2e.exec(child, [[require("eda").refresh_all()]])
  cursor_on("src/")
  e2e.feed(child, "<CR>")
  cursor_on("  inside")
  rename("src/", "lib/")
  rename("b", "new_b")
  fail_second("move")
  partial_then_retry()
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/lib/inside"), { "inside" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_b"), { "B" })
end

T["rejects a confirmation for buffer text that has changed"] = function()
  rename("a", "new_a")
  e2e.exec(
    child,
    [[
    require("eda.config").get().confirm = { move = true }
    require("eda.buffer.confirm").show = function(_, _, execute) _G.confirm_write = execute end
  ]]
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, "_G.confirm_write ~= nil")
  rename("b", "new_b")
  e2e.exec(child, "_G.confirm_write()")
  MiniTest.expect.equality(e2e.exec(child, "return #_G.results"), 0)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/b"), { "B" })
  MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified and vim.bo.modifiable"), true)
end

for _, entries in ipairs({ "created", "created_dir/\n  inside" }) do
  T["retains pending creates before the first line: " .. entries] = function()
    rename("a", "new_a")
    e2e.feed(child, "ggO")
    e2e.feed_insert(child, entries)
    e2e.exec(
      child,
      [[
    local Fs = require("eda.fs")
    local create = Fs.create
    Fs.create = function(_, _, callback)
      Fs.create = create
      callback("injected failure")
    end
  ]]
    )
    e2e.feed(child, ":w<CR>")
    e2e.wait_until(child, "#_G.results == 1 and vim.bo.modifiable")
    MiniTest.expect.equality(
      e2e.exec(
        child,
        string.format(
          [[
    return vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), %q)
  ]],
          entries:match("[^\n]+")
        )
      ),
      true
    )
    e2e.feed(child, ":w<CR>")
    e2e.wait_until(child, "#_G.results == 2 and not vim.bo.modified")
    MiniTest.expect.equality(
      vim.fn.filereadable(tmp .. (entries == "created" and "/created" or "/created_dir/inside")),
      1
    )
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_a"), { "A" })
  end
end

T["does not reconcile a partial result after a post hook closes the explorer"] = function()
  rename("a", "new_a")
  rename("b", "new_b")
  fail_second("move")
  e2e.exec(
    child,
    [[
    _G.closed_explorer = require("eda").get_current()
    vim.api.nvim_create_autocmd("User", {
      pattern = "EdaMutationPost",
      once = true,
      callback = function() require("eda").close() end,
    })
  ]]
  )
  e2e.feed(child, ":w<CR>")
  e2e.wait_until(child, [[#_G.results == 1 and require("eda").get_current() == nil]])
  MiniTest.expect.equality(
    e2e.exec(
      child,
      [[
    local ex = _G.closed_explorer
    return not ex._writing and ex.store:get_by_path(ex.root_path .. "/a") ~= nil
  ]]
    ),
    true
  )
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/new_a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/b"), { "B" })
end

return T
