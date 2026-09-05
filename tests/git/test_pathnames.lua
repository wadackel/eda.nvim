local git = require("eda.git")
local helpers = require("helpers")
local T = MiniTest.new_set()

T["NUL records preserve every pathname byte"] = function()
  local names = {
    "normal.txt",
    "space name",
    "日本語.txt",
    'quote"name',
    "a -> b",
    "line\nname",
    "cr\r\nname",
    "tab\tname",
    "back\\slash",
  }
  local records, expected, reported = {}, {}, {}
  for _, name in ipairs(names) do
    records[#records + 1] = "?? " .. name .. "\0"
    expected["/root/" .. name] = "?"
  end
  MiniTest.expect.equality(git._parse_status(table.concat(records), "/root", reported), expected)
  for _, name in ipairs(names) do
    MiniTest.expect.equality(reported["/root/" .. name], true)
  end
end

T["rename and copy consume destination then source fields"] = function()
  for _, code in ipairs({ "R ", " R", "C ", " C", "RM" }) do
    local reported = {}
    local output = code .. ' new/line\n -> name\0old/quote"name\0?? after\0!! ignored dir/\0'
    local result = git._parse_status(output, "/root", reported)
    local effective = code:sub(2, 2) ~= " " and code:sub(2, 2) or code:sub(1, 1)
    MiniTest.expect.equality(result, {
      ["/root/new/line\n -> name"] = effective,
      ["/root/new"] = effective,
      ["/root/after"] = "?",
      ["/root/ignored dir"] = "!",
    })
    MiniTest.expect.equality(reported, { ["/root/new/line\n -> name"] = true, ["/root/after"] = true })
  end
end

for _, quote_path in ipairs({ "true", "false" }) do
  T["real Git status preserves unusual names with core.quotePath=" .. quote_path] = function()
    local tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
    local function command(...)
      local args = { "git", "-C", tmp }
      vim.list_extend(args, { ... })
      local result = vim.system(args, { text = true }):wait()
      assert(result.code == 0, result.stderr)
    end
    local ok, err = pcall(function()
      command("init")
      command("config", "user.email", "test@test.com")
      command("config", "user.name", "Test")
      command("config", "core.quotePath", quote_path)
      command("config", "status.renames", "true")
      local src, dst = 'old "日本語" -> name', 'new "日本語" -> line\r\nname'
      helpers.create_file(tmp .. "/" .. src, "ORIGINAL")
      helpers.create_file(tmp .. "/.gitignore", "ignored/")
      command("add", ".")
      command("commit", "--no-gpg-sign", "-m", "fixture")
      command("mv", "--", src, dst)
      local names = {
        "space name",
        "日本語.txt",
        'quote"name',
        "a -> b",
        "line\nname",
        "cr\r\nname",
        "tab\tname",
        "back\\slash",
      }
      for _, name in ipairs(names) do
        helpers.create_file(tmp .. "/" .. name, name)
      end
      helpers.create_file(tmp .. "/ignored/inside", "IGNORED")
      local ready, statuses = false, nil
      git.status(tmp, function(value)
        ready, statuses = true, value
      end)
      helpers.wait_for(5000, function()
        return ready
      end)
      MiniTest.expect.equality(ready, true)
      for _, name in ipairs(names) do
        MiniTest.expect.equality(statuses[tmp .. "/" .. name], "?")
      end
      MiniTest.expect.equality(statuses[tmp .. "/" .. dst], "R")
      MiniTest.expect.equality(statuses[tmp .. "/" .. src], nil)
      MiniTest.expect.equality(statuses[tmp .. "/ignored"], "!")
      MiniTest.expect.equality(git.is_gitignored(statuses, tmp .. "/ignored/inside"), true)
      local reported = git.get_reported_changes(tmp)
      MiniTest.expect.equality(reported[tmp .. "/" .. dst], true)
      MiniTest.expect.equality(reported[tmp .. "/ignored"], nil)
      MiniTest.expect.equality(git.get_cached(tmp), statuses)
    end)
    git.invalidate(tmp)
    helpers.remove_temp_dir(tmp)
    assert(ok, err)
  end
end

return T
