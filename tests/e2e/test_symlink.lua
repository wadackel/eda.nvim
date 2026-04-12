local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["symlink"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/real_file.txt", "hello")
      e2e.create_dir(tmp .. "/real_dir")
      e2e.create_file(tmp .. "/real_dir/inner.txt", "world")
      -- Create symlinks
      vim.uv.fs_symlink(tmp .. "/real_file.txt", tmp .. "/link_file.txt")
      vim.uv.fs_symlink(tmp .. "/real_dir", tmp .. "/link_dir")
      vim.uv.fs_symlink(tmp .. "/nonexistent", tmp .. "/broken_link")
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["symlink"]["shows link target suffix for valid symlinks"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 80 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for decoration cache to be populated
  e2e.wait_until(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local cache = painter._decoration_cache
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    return count > 0
  ]],
    5000
  )

  -- Check that link_file.txt has link_suffix in the decoration cache
  local has_link_suffix = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local store = explorer.store
    local found = false
    for node_id, entry in pairs(painter._decoration_cache) do
      if entry.link_suffix then
        local node = store:get(node_id)
        if node and node.name:find("link_file") then
          found = true
        end
      end
    end
    return found
  ]]
  )
  MiniTest.expect.equality(has_link_suffix, true)

  -- Check that broken_link does NOT have link_suffix
  local broken_has_no_suffix = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local store = explorer.store
    for node_id, entry in pairs(painter._decoration_cache) do
      if entry.link_suffix then
        local node = store:get(node_id)
        if node and node.name:find("broken_link") then
          return false
        end
      end
    end
    return true
  ]]
  )
  MiniTest.expect.equality(broken_has_no_suffix, true)
end

T["symlink"]["shows trailing slash for directory symlink suffix"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 80 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  e2e.wait_until(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local cache = painter._decoration_cache
    local count = 0
    for _ in pairs(cache) do count = count + 1 end
    return count > 0
  ]],
    5000
  )

  -- Check that link_dir has link_suffix ending with /
  local dir_suffix_has_slash = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local store = explorer.store
    for node_id, entry in pairs(painter._decoration_cache) do
      if entry.link_suffix then
        local node = store:get(node_id)
        if node and node.name:find("link_dir") then
          return entry.link_suffix:sub(-1) == "/"
        end
      end
    end
    return false
  ]]
  )
  MiniTest.expect.equality(dir_suffix_has_slash, true)
end

return T
