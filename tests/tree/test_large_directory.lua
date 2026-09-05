local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local helpers = require("helpers")
local tmp, notify, warnings, scanners
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = vim.uv.fs_realpath(helpers.create_temp_dir())
      warnings, scanners = {}, {}
      notify = vim.notify
      vim.notify = function(message, level)
        warnings[#warnings + 1] = { message = message, level = level }
      end
    end,
    post_case = function()
      for _, scanner in ipairs(scanners) do
        scanner:dispose()
      end
      vim.notify = notify
      helpers.remove_temp_dir(tmp)
    end,
  },
})
local function new_scanner(opts)
  local store = Store.new()
  store:set_root(tmp)
  local scanner = Scanner.new(store, opts)
  scanners[#scanners + 1] = scanner
  return scanner, store
end
local function scan(scanner, id)
  local done, failure = false, nil
  scanner:scan(id, function(err)
    done, failure = true, err
  end)
  MiniTest.expect.equality(
    helpers.wait_for(3000, function()
      return done
    end),
    true
  )
  MiniTest.expect.equality(failure, nil)
end
for _, nested in ipairs({ false, true }) do
  for count = 2, 4 do
    T[(nested and "nested" or "root") .. " directory with " .. count .. " entries at threshold 3"] = function()
      local path = nested and tmp .. "/nested" or tmp
      helpers.create_dir(path)
      for i = 1, count do
        helpers.create_file(path .. "/file" .. i, "file")
      end
      local scanner, store = new_scanner({ large_dir_threshold = 3 })
      scan(scanner, store.root_id)
      local node = store:get_by_path(path)
      if nested then
        scan(scanner, node.id)
      end
      MiniTest.expect.equality(#store:children(node.id), count)
      MiniTest.expect.equality(#warnings, count > 3 and 1 or 0)
      if count > 3 then
        MiniTest.expect.equality(warnings[1], {
          message = "eda: " .. path .. " contains 4 entries (large_dir_threshold = 3)",
          level = vim.log.levels.WARN,
        })
      end
    end
  end
end
T["counts raw immediate entries before filtering and resolves no descendants"] = function()
  helpers.create_file(tmp .. "/.hidden", "hidden")
  helpers.create_file(tmp .. "/ignored", "ignored")
  helpers.create_file(tmp .. "/directory/child", "child")
  assert(vim.uv.fs_symlink(tmp .. "/directory", tmp .. "/link"))
  local scanner, store =
    new_scanner({ large_dir_threshold = 3, show_hidden = false, ignore_patterns = { "^ignored$" } })
  local done = false
  scanner:scan(store.root_id, function(err)
    MiniTest.expect.equality(err, nil)
    done = true
  end)
  MiniTest.expect.equality(#warnings, 0)
  MiniTest.expect.equality(done, false)
  MiniTest.expect.equality(
    helpers.wait_for(3000, function()
      return done
    end),
    true
  )
  MiniTest.expect.equality(#warnings, 1)
  MiniTest.expect.equality(warnings[1].message, "eda: " .. tmp .. " contains 4 entries (large_dir_threshold = 3)")
  MiniTest.expect.equality(#store:children(store.root_id), 2)
  MiniTest.expect.equality(store:get_by_path(tmp .. "/directory/child"), nil)
end
T["deduplicates warnings across rescans and replacement scanners"] = function()
  helpers.create_file(tmp .. "/one", "one")
  helpers.create_file(tmp .. "/two", "two")
  local scanner, store = new_scanner({ large_dir_threshold = 1 })
  scan(scanner, store.root_id)
  scan(scanner, store.root_id)
  scanner:dispose()
  local replacement, replacement_store = new_scanner({ large_dir_threshold = 1 })
  scan(replacement, replacement_store.root_id)
  MiniTest.expect.equality(#warnings, 1)
end
T["zero disables warnings without suppressing scanning"] = function()
  helpers.create_file(tmp .. "/one", "one")
  local scanner, store = new_scanner({ large_dir_threshold = 0 })
  scan(scanner, store.root_id)
  MiniTest.expect.equality(#warnings, 0)
  MiniTest.expect.equality(#store:children(store.root_id), 1)
end
T["cancelled enumeration neither warns nor consumes the later warning"] = function()
  helpers.create_file(tmp .. "/one", "one")
  helpers.create_file(tmp .. "/two", "two")
  local scanner, store = new_scanner({ large_dir_threshold = 1 })
  local done, failure = false, nil
  scanner:scan(store.root_id, function(err)
    done, failure = true, err
  end)
  scanner:dispose()
  MiniTest.expect.equality(
    helpers.wait_for(3000, function()
      return done
    end),
    true
  )
  MiniTest.expect.equality(failure, "scan cancelled")
  MiniTest.expect.equality(#warnings, 0)
  local replacement, replacement_store = new_scanner({ large_dir_threshold = 1 })
  scan(replacement, replacement_store.root_id)
  MiniTest.expect.equality(#warnings, 1)
end
return T
