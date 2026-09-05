local Preview = require("eda.preview")
local Store = require("eda.tree.store")
local config = require("eda.config")
local helpers = require("helpers")
local preview, tmp, filer, buffer, reads, original_read

local function flush()
  local done = false
  vim.schedule(function()
    done = true
  end)
  helpers.wait_for(1000, function()
    return done
  end)
  MiniTest.expect.equality(done, true)
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      config.setup({
        preview = { enabled = true, debounce = 1000 },
        icon = { provider = "none" },
        git = { enabled = false },
      })
      tmp = helpers.create_temp_dir()
      helpers.create_file(tmp .. "/file.txt", "FILE")
      helpers.create_file(tmp .. "/next.txt", "NEXT")
      buffer = vim.api.nvim_create_buf(false, true)
      vim.cmd("topleft vsplit")
      filer = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(filer, buffer)
      vim.api.nvim_win_set_width(filer, math.floor(vim.o.columns * 0.3))
      preview = Preview.new(config.get().preview)
      preview:attach({
        winid = filer,
        kind = "split_left",
        config = config.get(),
        is_visible = function()
          return true
        end,
      })
      reads = {}
      original_read = vim.uv.fs_read
      vim.uv.fs_read = function(fd, _, _, callback)
        local read = { fd = fd, done = false }
        read.finish = function(data)
          read.done = true
          callback(nil, data)
        end
        reads[#reads + 1] = read
      end
    end,
    post_case = function()
      preview:close()
      vim.uv.fs_read = original_read
      for _, read in ipairs(reads) do
        if not read.done then
          vim.uv.fs_close(read.fd)
        end
      end
      if vim.api.nvim_win_is_valid(filer) then
        vim.api.nvim_win_close(filer, true)
      end
      if vim.api.nvim_buf_is_valid(buffer) then
        vim.api.nvim_buf_delete(buffer, { force = true })
      end
      helpers.remove_temp_dir(tmp)
    end,
  },
})

local function show_read(path, count)
  preview:show(path)
  helpers.wait_for(1000, function()
    return #reads == count
  end)
  MiniTest.expect.equality(#reads, count)
end

for _, action in ipairs({ "close", "disable", "disable_and_close" }) do
  T[action .. " prevents a pending text read from opening a preview"] = function()
    show_read(tmp .. "/file.txt", 1)
    if action ~= "close" then
      preview:set_enabled(false)
    end
    if action ~= "disable" then
      preview:close()
    end
    reads[1].finish("STALE")
    flush()
    MiniTest.expect.equality(preview.winid, nil)
  end
end

T["same-path close and reopen rejects the earlier read"] = function()
  show_read(tmp .. "/file.txt", 1)
  preview:close()
  show_read(tmp .. "/file.txt", 2)
  reads[2].finish("NEW")
  flush()
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.bufnr, 0, -1, false), { "NEW" })
  reads[1].finish("OLD")
  flush()
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(preview.bufnr, 0, -1, false), { "NEW" })
end

T["a new debounced target immediately supersedes an outstanding read"] = function()
  show_read(tmp .. "/file.txt", 1)
  preview:update({ type = "file", path = tmp .. "/next.txt" })
  reads[1].finish("STALE")
  flush()
  MiniTest.expect.equality(preview.winid, nil)
end

local function directory_request()
  local store = Store.new()
  store:set_root(tmp)
  local node = store:get(store.root_id)
  local complete
  local scanner = {
    scan = function(_, _, callback)
      complete = callback
    end,
  }
  preview:attach(
    preview.window,
    { store = store, scanner = scanner, decorator_chain = require("eda.render.decorator").Chain.new() }
  )
  preview:show_directory(node)
  MiniTest.expect.equality(type(complete), "function")
  return store, node, function()
    node.children_state = "loaded"
    complete()
    flush()
  end
end

T["close invalidates a pending directory scan"] = function()
  local _, _, complete = directory_request()
  preview:close()
  complete()
  MiniTest.expect.equality(preview.winid, nil)
end

T["reattach invalidates directory requests with a reused node ID"] = function()
  local _, _, complete = directory_request()
  local replacement = Store.new()
  replacement:set_root(tmp .. "/replacement")
  local root = replacement:get(replacement.root_id)
  root.children_state = "loaded"
  preview:attach(
    preview.window,
    { store = replacement, scanner = {}, decorator_chain = require("eda.render.decorator").Chain.new() }
  )
  complete()
  MiniTest.expect.equality(preview.winid, nil)
  preview:show_directory(root)
  MiniTest.expect.equality(preview.winid ~= nil, true)
end

T["closing from a FileType callback prevents subsequent presentation"] = function()
  helpers.create_file(tmp .. "/file.lua", "return {}")
  local closed, cancelled_buf = false, nil
  local hook = vim.api.nvim_create_autocmd("FileType", {
    pattern = "lua",
    once = true,
    callback = function(args)
      closed = true
      cancelled_buf = args.buf
      preview:close()
    end,
  })
  local ok, err = pcall(function()
    show_read(tmp .. "/file.lua", 1)
    reads[1].finish("return {}")
    flush()
    MiniTest.expect.equality(closed, true)
    MiniTest.expect.equality(preview.winid, nil)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(cancelled_buf), false)
  end)
  pcall(vim.api.nvim_del_autocmd, hook)
  assert(ok, err)
end

T["disabled updates do not reconfigure a filer that has no preview"] = function()
  local original = vim.api.nvim_win_set_config
  local changes = 0
  vim.api.nvim_win_set_config = function()
    changes = changes + 1
  end
  preview.window.kind = "float"
  preview:set_enabled(false)
  local ok, err = pcall(function()
    preview:update(nil)
  end)
  vim.api.nvim_win_set_config = original
  preview.window.kind = "split_left"
  assert(ok, err)
  MiniTest.expect.equality(changes, 0)
end

T["suspending rejects a pending text read"] = function()
  show_read(tmp .. "/file.txt", 1)
  preview:suspend()
  reads[1].finish("STALE")
  flush()
  MiniTest.expect.equality(preview.winid, nil)
end

T["suspending does not change the enabled state"] = function()
  preview:suspend()
  MiniTest.expect.equality(preview:is_enabled(), true)
  MiniTest.expect.equality(preview:_is_suspended(), true)
  preview:resume()
  MiniTest.expect.equality(preview:is_enabled(), true)
end

local function counting_window()
  local resolved = 0
  local window = {
    winid = filer,
    kind = "split_left",
    config = config.get(),
    is_visible = function()
      return true
    end,
  }
  preview:attach(window, nil, function()
    resolved = resolved + 1
    return nil
  end)
  return function()
    return resolved
  end
end

T["resume ignores a suspension that was never set"] = function()
  local resolved = counting_window()
  preview:resume()
  MiniTest.expect.equality(preview:_is_suspended(), false)
  -- Dropping resume()'s guard would take this through try_resume and resolve a target.
  MiniTest.expect.equality(resolved(), 0)
end

T["reattaching clears suspension so a reattached preview cannot wedge"] = function()
  preview:suspend()
  MiniTest.expect.equality(preview:_is_suspended(), true)
  preview:attach({
    winid = filer,
    kind = "split_left",
    config = config.get(),
    is_visible = function()
      return true
    end,
  })
  MiniTest.expect.equality(preview:_is_suspended(), false)
end

T["try_resume keeps a preview hidden while the suspension stands"] = function()
  local resolved = counting_window()
  preview:suspend()

  preview:try_resume()
  MiniTest.expect.equality(preview:_is_suspended(), true)
  MiniTest.expect.equality(preview.winid, nil)
  -- Dropping try_resume()'s suspension guard would resolve a target here.
  MiniTest.expect.equality(resolved(), 0)

  preview:resume()
  MiniTest.expect.equality(preview:_is_suspended(), false)
  MiniTest.expect.equality(resolved(), 1)
end

T["try_resume does not resolve a target while the owner hides the explorer"] = function()
  preview:attach(
    {
      winid = filer,
      kind = "split_left",
      config = config.get(),
      is_visible = function()
        return false
      end,
    },
    nil,
    function()
      error("target must not be resolved for a hidden explorer")
    end
  )
  preview:try_resume()
  MiniTest.expect.equality(preview.winid, nil)
end

return T
