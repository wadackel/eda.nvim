local Fs = require("eda.fs")
local helpers = require("helpers")
local tmp, original, calls, platform, available, result
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = helpers.create_temp_dir()
      original = {
        uname = vim.uv.os_uname,
        executable = vim.fn.executable,
        system = vim.system,
        health = vim.health,
        trash = require("eda.config").get().delete_to_trash,
      }
      calls, platform, available = {}, "Linux", {}
      result = { code = 0, stderr = "" }
      vim.uv.os_uname = function()
        return { sysname = platform }
      end
      vim.fn.executable = function(name)
        return available[name] and 1 or 0
      end
      vim.system = function(command, _, callback)
        calls[#calls + 1] = command
        callback(result)
        return {}
      end
    end,
    post_case = function()
      vim.uv.os_uname = original.uname
      vim.fn.executable = original.executable
      vim.system = original.system
      vim.health = original.health
      require("eda.config").get().delete_to_trash = original.trash
      helpers.remove_temp_dir(tmp)
    end,
  },
})

local function trash(path)
  local done, err, fast = false, nil, nil
  Fs.trash(path, function(value)
    done, err, fast = true, value, vim.in_fast_event()
  end)
  helpers.wait_for(5000, function()
    return done
  end)
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(fast, false)
  return err
end

for _, system in ipairs({ "Darwin", "Linux" }) do
  T[system .. " preserves files when the trash backend is absent"] = function()
    platform = system
    helpers.create_file(tmp .. "/keep", "KEEP")
    MiniTest.expect.equality(type(trash(tmp .. "/keep")), "string")
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
    MiniTest.expect.equality(#calls, 0)
  end

  T[system .. " passes the path as a separate backend argument"] = function()
    platform = system
    local backend = system == "Darwin" and "osascript" or "trash-put"
    available[backend] = true
    local path = tmp .. '/a "quoted" \\ path'
    helpers.create_file(path, "KEEP")
    MiniTest.expect.equality(trash(path), nil)
    MiniTest.expect.equality(#calls, 1)
    MiniTest.expect.equality(calls[1][1], backend)
    MiniTest.expect.equality(calls[1][#calls[1]], path)
    MiniTest.expect.equality(calls[1][#calls[1] - 1], "--")
    if system == "Darwin" then
      MiniTest.expect.equality(calls[1][3]:find(path, 1, true), nil)
    end
  end

  T[system .. " reports backend failure without permanent fallback"] = function()
    platform = system
    available[system == "Darwin" and "osascript" or "trash-put"] = true
    result = { code = 1, stderr = "permission denied" }
    helpers.create_file(tmp .. "/keep", "KEEP")
    MiniTest.expect.equality(trash(tmp .. "/keep"):find("permission denied", 1, true) ~= nil, true)
    MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
    MiniTest.expect.equality(#calls, 1)
  end
end

T["spawn failure is returned and preserves the source"] = function()
  available["trash-put"] = true
  vim.system = function()
    error("ENOENT: executable disappeared")
  end
  helpers.create_file(tmp .. "/keep", "KEEP")
  MiniTest.expect.equality(trash(tmp .. "/keep"):find("ENOENT", 1, true) ~= nil, true)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
end

T["option-like paths are passed after the option terminator"] = function()
  available["trash-put"] = true
  MiniTest.expect.equality(trash("--version"), nil)
  MiniTest.expect.equality(calls[1], { "trash-put", "--", "--version" })
end

T["explicit permanent deletion works without a trash backend"] = function()
  helpers.create_file(tmp .. "/delete", "DELETE")
  local completed
  Fs.execute_operations({ { type = "delete", path = tmp .. "/delete" } }, { delete_to_trash = false }, function(value)
    completed = value
  end)
  helpers.wait_for(5000, function()
    return completed ~= nil
  end)
  MiniTest.expect.equality(completed.error, nil)
  MiniTest.expect.equality(#completed.completed, 1)
  MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/delete"), nil)
  MiniTest.expect.equality(#calls, 0)
end

T["a missing backend fails the mutation result and leaves later operations unattempted"] = function()
  helpers.create_file(tmp .. "/keep", "KEEP")
  local completed
  local operations = {
    { type = "delete", path = tmp .. "/keep" },
    { type = "create", path = tmp .. "/later", entry_type = "file" },
  }
  Fs.execute_operations(operations, { delete_to_trash = true }, function(value)
    completed = value
  end)
  MiniTest.expect.equality(completed.failed, operations[1])
  MiniTest.expect.equality(type(completed.error), "string")
  MiniTest.expect.equality(#completed.completed, 0)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/keep"), { "KEEP" })
  MiniTest.expect.equality(vim.uv.fs_lstat(tmp .. "/later"), nil)
end

T["health reports missing available and explicitly disabled trash"] = function()
  local messages = {}
  vim.health = {}
  for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
    vim.health[level] = function(message)
      messages[#messages + 1] = level .. ":" .. message
    end
  end
  local function check()
    messages = {}
    require("eda.health").check()
    return table.concat(messages, "\n")
  end
  require("eda.config").get().delete_to_trash = true
  MiniTest.expect.equality(check():find("warn:System trash unavailable", 1, true) ~= nil, true)
  available["trash-put"] = true
  MiniTest.expect.equality(check():find("ok:System trash: trash-put", 1, true) ~= nil, true)
  require("eda.config").get().delete_to_trash = false
  MiniTest.expect.equality(check():find("info:Permanent deletion is enabled", 1, true) ~= nil, true)
end

return T
