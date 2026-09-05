local git = require("eda.git")
local helpers = require("helpers")
local tmp, system, jobs, notified, notify
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
      helpers.create_dir(tmp .. "/.git")
      helpers.create_dir(tmp .. "/nested")
      git.invalidate(tmp)
      jobs, notified = {}, {}
      system, notify = vim.system, vim.notify
      vim.notify = function(message)
        notified[#notified + 1] = message
      end
      vim.system = function(command, opts, callback)
        jobs[#jobs + 1] = { command = command, opts = opts, callback = callback }
        return { kill = function() end }
      end
    end,
    post_case = function()
      git.invalidate(tmp)
      vim.system, vim.notify = system, notify
      helpers.remove_temp_dir(tmp)
    end,
  },
})
local function wait_for(predicate)
  MiniTest.expect.equality(helpers.wait_for(3000, predicate), true)
end
local function complete(index, output, code)
  jobs[index].callback({ code = code or 0, stdout = output or "", stderr = "failed" })
end
T["batches same-tick equivalent requests and fans out one result"] = function()
  local called = 0
  for i = 1, 20 do
    git.status(i % 2 == 0 and tmp .. "/nested" or tmp, function(value)
      MiniTest.expect.equality(value[tmp .. "/new.txt"], "?")
      called = called + 1
    end)
  end
  wait_for(function()
    return #jobs > 0
  end)
  MiniTest.expect.equality(#jobs, 1)
  MiniTest.expect.equality(git.get_status_ready(tmp), "loading")
  MiniTest.expect.equality(vim.tbl_contains(jobs[1].command, "--no-optional-locks"), true)
  MiniTest.expect.equality(vim.tbl_contains(jobs[1].command, "-z"), true)
  MiniTest.expect.equality(jobs[1].opts.text, nil)
  complete(1, "?? new.txt\0")
  wait_for(function()
    return called == 20
  end)
  MiniTest.expect.equality(git.get_status_ready(tmp), "ready")
end
T["requests during an active command share one fresh follow-up"] = function()
  local first, later = 0, 0
  git.status(tmp, function(value)
    MiniTest.expect.equality(value[tmp .. "/first"], "M")
    first = first + 1
  end)
  wait_for(function()
    return #jobs == 1
  end)
  for _ = 1, 10 do
    git.status(tmp, function(value)
      MiniTest.expect.equality(value[tmp .. "/later"], "?")
      later = later + 1
    end)
  end
  MiniTest.expect.equality(#jobs, 1)
  complete(1, " M first\0")
  wait_for(function()
    return #jobs == 2
  end)
  MiniTest.expect.equality(first, 1)
  MiniTest.expect.equality(later, 0)
  MiniTest.expect.equality(git.get_cached(tmp)[tmp .. "/first"], "M")
  MiniTest.expect.equality(git.get_status_ready(tmp), "ready")
  complete(2, "?? later\0")
  wait_for(function()
    return later == 10
  end)
  MiniTest.expect.equality(#jobs, 2)
end
T["invalidation rejects an active result and serializes a newer request"] = function()
  local old, fresh = 0, 0
  git.status(tmp, function(value)
    MiniTest.expect.equality(value, nil)
    old = old + 1
  end)
  wait_for(function()
    return #jobs == 1
  end)
  git.invalidate(tmp)
  git.status(tmp, function(value)
    MiniTest.expect.equality(value[tmp .. "/fresh"], "M")
    fresh = fresh + 1
  end)
  MiniTest.expect.equality(#jobs, 1)
  complete(1, "?? stale\0")
  wait_for(function()
    return #jobs == 2
  end)
  MiniTest.expect.equality(old, 1)
  MiniTest.expect.equality(git.get_cached(tmp), nil)
  complete(2, " M fresh\0")
  wait_for(function()
    return fresh == 1
  end)
  complete(1, "?? stale\0")
  complete(2, "?? duplicate\0")
  vim.schedule(function()
    fresh = fresh + 10
  end)
  wait_for(function()
    return fresh == 11
  end)
  MiniTest.expect.equality(old, 1)
  MiniTest.expect.equality(git.get_cached(tmp), { [tmp .. "/fresh"] = "M" })
end
T["invalidation without another request settles subscribers without restoring cache"] = function()
  local called = 0
  git.status(tmp, function(value)
    MiniTest.expect.equality(value, nil)
    called = called + 1
  end)
  wait_for(function()
    return #jobs == 1
  end)
  git.invalidate(tmp)
  complete(1, "?? stale\0")
  wait_for(function()
    return called == 1
  end)
  MiniTest.expect.equality(git.get_cached(tmp), nil)
  MiniTest.expect.equality(git.get_status_ready(tmp), nil)
end
T["invalidation cancels a scheduled request before subprocess creation"] = function()
  local called = 0
  git.status(tmp, function(value)
    MiniTest.expect.equality(value, nil)
    called = called + 1
  end)
  git.invalidate(tmp)
  wait_for(function()
    return called == 1
  end)
  MiniTest.expect.equality(#jobs, 0)
end
T["first-load failure is terminal and refresh failure retains usable data"] = function()
  local called = 0
  local function callback()
    called = called + 1
  end
  git.status(tmp, callback)
  wait_for(function()
    return #jobs == 1
  end)
  complete(1, "", 128)
  wait_for(function()
    return called == 1
  end)
  MiniTest.expect.equality(git.get_status_ready(tmp), "error")
  git.status(tmp, callback)
  wait_for(function()
    return #jobs == 2
  end)
  complete(2, " M known\0")
  wait_for(function()
    return called == 2
  end)
  git.status(tmp, callback)
  wait_for(function()
    return #jobs == 3
  end)
  MiniTest.expect.equality(git.get_status_ready(tmp), "ready")
  MiniTest.expect.equality(git.get_cached(tmp)[tmp .. "/known"], "M")
  complete(3, "", 128)
  wait_for(function()
    return called == 3
  end)
  MiniTest.expect.equality(git.get_status_ready(tmp), "ready")
  MiniTest.expect.equality(git.get_cached(tmp)[tmp .. "/known"], "M")
end
T["submission failure settles all batched callbacks"] = function()
  vim.system = function()
    error("spawn failed")
  end
  local called = 0
  for _ = 1, 4 do
    git.status(tmp, function(value)
      MiniTest.expect.equality(value, nil)
      called = called + 1
    end)
  end
  wait_for(function()
    return called == 4
  end)
  MiniTest.expect.equality(git.get_status_ready(tmp), "error")
end
T["one failing subscriber does not strand other subscribers or reentrant requests"] = function()
  local called = 0
  git.status(tmp, function()
    error("observer failed")
  end)
  git.status(tmp, function()
    called = called + 1
    git.status(tmp, function()
      called = called + 1
    end)
  end)
  wait_for(function()
    return #jobs == 1
  end)
  complete(1, "?? one\0")
  wait_for(function()
    return #jobs == 2 and #notified == 1
  end)
  complete(2, "?? two\0")
  wait_for(function()
    return called == 2
  end)
end
T["different repositories can finish in reverse order"] = function()
  helpers.create_dir(tmp .. "/nested/.git")
  git.invalidate(tmp .. "/nested")
  local called = 0
  git.status(tmp, function()
    called = called + 1
  end)
  git.status(tmp .. "/nested", function()
    called = called + 1
  end)
  wait_for(function()
    return #jobs == 2
  end)
  complete(2, "?? nested-file\0")
  complete(1, " M root-file\0")
  wait_for(function()
    return called == 2
  end)
  MiniTest.expect.equality(git.get_cached(tmp), { [tmp .. "/root-file"] = "M" })
  MiniTest.expect.equality(git.get_cached(tmp .. "/nested"), { [tmp .. "/nested/nested-file"] = "?" })
  git.invalidate(tmp .. "/nested")
end
return T
