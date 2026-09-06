local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

local COLLECT = [[
  _G.events = {}
  vim.api.nvim_create_autocmd("User", {
    pattern = { "EdaTreeOpen", "EdaTreeClose" },
    callback = function(args)
      table.insert(_G.events, { name = args.match, data = vim.deepcopy(args.data) })
    end,
  })
]]

T["tree events"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/file.txt", "hello")
      e2e.exec(child, COLLECT)
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

local function events()
  return e2e.exec(child, "return _G.events")
end

T["tree events"]["EdaTreeOpen carries the root and the instance it opened"] = function()
  e2e.open_eda(child, tmp)
  e2e.wait_until(child, "#_G.events >= 1", 10000)

  local instance_id = e2e.exec(child, [[return require("eda").get_current().instance_id]])
  local recorded = events()
  MiniTest.expect.equality(recorded[1].name, "EdaTreeOpen")
  MiniTest.expect.equality(recorded[1].data.root_path, tmp)
  MiniTest.expect.equality(recorded[1].data.instance_id, instance_id)
end

T["tree events"]["EdaTreeClose carries the root and the instance that closed"] = function()
  e2e.open_eda(child, tmp)
  e2e.wait_until(child, "#_G.events >= 1", 10000)
  local instance_id = e2e.exec(child, [[return require("eda").get_current().instance_id]])

  e2e.exec(child, [[require("eda").close()]])
  e2e.wait_until(child, "#_G.events >= 2", 10000)

  local recorded = events()
  MiniTest.expect.equality(recorded[2].name, "EdaTreeClose")
  MiniTest.expect.equality(recorded[2].data.root_path, tmp)
  MiniTest.expect.equality(recorded[2].data.instance_id, instance_id)
end

-- The identifying case: two explorers share a root, so only the instance id can say
-- which one closed. The closing explorer is already out of `get_all()` when the event
-- fires, so a listener has no way to look it up.
T["tree events"]["EdaTreeClose identifies which of two explorers on one root closed"] = function()
  e2e.open_eda(child, tmp)
  e2e.exec(child, string.format([[require("eda").open_split(%q)]], tmp))
  e2e.wait_until(child, "#require('eda').get_all() == 2", 10000)

  local ids = e2e.exec(
    child,
    [[
    local out = {}
    for i, e in ipairs(require("eda").get_all()) do
      out[i] = e.instance_id
    end
    return out
  ]]
  )
  MiniTest.expect.equality(ids[1] ~= ids[2], true)

  -- Close the first, which is not the current one.
  e2e.exec(child, [[require("eda").close(require("eda").get_all()[1])]])
  e2e.wait_until(child, "#require('eda').get_all() == 1", 10000)

  local recorded = events()
  local last = recorded[#recorded]
  MiniTest.expect.equality(last.name, "EdaTreeClose")
  MiniTest.expect.equality(last.data.instance_id, ids[1])
  MiniTest.expect.equality(e2e.exec(child, [[return require("eda").get_all()[1].instance_id]]), ids[2])
end

return T
