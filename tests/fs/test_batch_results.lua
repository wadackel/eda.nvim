local Fs = require("eda.fs")
local helpers = require("helpers")
local originals, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      originals = { create = Fs.create, copy = Fs.copy, system = vim.system, exec = vim.api.nvim_exec_autocmds }
      tmp = helpers.create_temp_dir()
    end,
    post_case = function()
      Fs.create, Fs.copy = originals.create, originals.copy
      vim.system, vim.api.nvim_exec_autocmds = originals.system, originals.exec
      helpers.remove_temp_dir(tmp)
    end,
  },
})

local function run(ops, opts)
  local result
  Fs.execute_operations(ops, opts or { delete_to_trash = false }, function(value)
    result = value
  end)
  helpers.wait_for(3000, function()
    return result ~= nil
  end)
  return result
end

T["executes copy before a dependent move"] = function()
  helpers.create_file(tmp .. "/source", "source")
  local ops = {
    { type = "copy", src = tmp .. "/source", dst = tmp .. "/copy" },
    { type = "move", src = tmp .. "/copy", dst = tmp .. "/moved" },
  }
  local result = run(ops, { delete_to_trash = false, no_replace = true })
  MiniTest.expect.equality(result.completed, ops)
  MiniTest.expect.equality(result.error, nil)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/moved"), { "source" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "source" })
end

T["reports a synchronous dispatch error without attempting the next operation"] = function()
  local calls = 0
  Fs.create = function()
    calls = calls + 1
    error("dispatch failed")
  end
  local ops = { { type = "create", path = "a" }, { type = "create", path = "b" } }
  local result = run(ops)
  MiniTest.expect.equality(calls, 1)
  MiniTest.expect.equality(result.completed, {})
  MiniTest.expect.equality(result.failed, ops[1])
  MiniTest.expect.equality(result.error:find("dispatch failed", 1, true) ~= nil, true)
end

T["ignores duplicate callbacks and settles the batch once"] = function()
  local pending, calls, results = {}, 0, {}
  Fs.create = function(_, _, cb)
    calls = calls + 1
    pending[calls] = cb
  end
  local ops = { { type = "create", path = "a" }, { type = "create", path = "b" } }
  Fs.execute_operations(ops, { delete_to_trash = false }, function(result)
    results[#results + 1] = result
  end)
  pending[1]()
  pending[1]("late error")
  pending[2]()
  pending[2]()
  MiniTest.expect.equality(calls, 2)
  MiniTest.expect.equality(#results, 1)
  MiniTest.expect.equality(results[1].completed, ops)
end

T["does not turn a completion callback error into an operation failure"] = function()
  Fs.create = function(_, _, cb)
    cb()
  end
  local calls = 0
  local ok, err = pcall(
    Fs.execute_operations,
    { { type = "create", path = "a" } },
    { delete_to_trash = false },
    function()
      calls = calls + 1
      error("completion failed")
    end
  )
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(tostring(err):find("completion failed", 1, true) ~= nil, true)
  MiniTest.expect.equality(calls, 1)
end

for _, failure in ipairs({ "parent", "spawn" }) do
  T["copy reports " .. failure .. " failures through the result"] = function()
    helpers.create_file(tmp .. "/source", "source")
    if failure == "parent" then
      helpers.create_file(tmp .. "/blocked", "blocker")
    else
      vim.system = function()
        error("spawn failed")
      end
    end
    local result = run({ { type = "copy", src = tmp .. "/source", dst = tmp .. "/blocked/target" } })
    MiniTest.expect.equality(#result.completed, 0)
    local message = failure == "parent" and "Failed to create destination parent" or "Failed to start cp"
    MiniTest.expect.equality(result.error:find(message, 1, true) ~= nil, true)
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/source"), { "source" })
  end
end

T["hook dispatch failures do not suppress execution or completion"] = function()
  local events, result = {}, nil
  vim.api.nvim_exec_autocmds = function(_, opts)
    events[#events + 1] = opts.pattern
    error("hook failed")
  end
  require("eda.mutation").execute(
    { { type = "create", path = tmp .. "/new" } },
    { delete_to_trash = false },
    function(value)
      result = value
    end
  )
  helpers.wait_for(3000, function()
    return result ~= nil
  end)
  MiniTest.expect.equality(events, { "EdaMutationPre", "EdaMutationPost" })
  MiniTest.expect.equality(#result.completed, 1)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/new"), 1)
end

T["empty mutation plans emit no events"] = function()
  local events, result = {}, nil
  vim.api.nvim_exec_autocmds = function(_, opts)
    events[#events + 1] = opts.pattern
  end
  require("eda.mutation").execute({}, { delete_to_trash = false }, function(value)
    result = value
  end)
  MiniTest.expect.equality(events, {})
  MiniTest.expect.equality(result.completed, {})
end

return T
