local e2e = require("e2e.helpers")
local child, tmp
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      e2e.setup_eda(child)
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      for _, name in ipairs({ "a", "b", "c" }) do
        e2e.create_file(tmp .. "/" .. name, name)
      end
      e2e.create_file(tmp .. "/dest/keep", "KEEP")
      e2e.exec(
        child,
        [[
        _G.events = {}
        vim.api.nvim_create_autocmd("User", {
          pattern = { "EdaMutationPre", "EdaMutationPost" },
          callback = function(args)
            table.insert(_G.events, { name = args.match, data = vim.deepcopy(args.data) })
          end,
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

local function prepare(entry)
  local paste = entry == "copy-paste" or entry == "cut-paste"
  e2e.open_eda(child, paste and (tmp .. "/dest") or tmp)
  if paste then
    e2e.exec(
      child,
      string.format(
        [[
      require("eda.register").set({ %q, %q, %q }, %q)
    ]],
        tmp .. "/a",
        tmp .. "/b",
        tmp .. "/c",
        entry == "cut-paste" and "cut" or "copy"
      )
    )
  elseif entry == "write" then
    e2e.feed(child, "Go")
    e2e.feed_insert(child, "new_a\nnew_b\nnew_c")
  else
    e2e.exec(
      child,
      [[
      for _, node in pairs(require("eda").get_current().store.nodes) do
        if node.name == "a" or node.name == "b" or node.name == "c" then node._marked = true end
      end
    ]]
    )
  end
end

local function inject(entry, scenario)
  local method = ({
    write = "create",
    delete = "delete",
    duplicate = "copy",
    ["copy-paste"] = "copy",
    ["cut-paste"] = "move",
  })[entry]
  e2e.exec(
    child,
    string.format(
      [[
    local Fs = require("eda.fs")
    local original = Fs[%q]
    local scenario = %q
    _G.calls = 0
    Fs[%q] = function(...)
      _G.calls = _G.calls + 1
      local args = { ... }
      local slot = %d
      local callback = args[slot]
      if (scenario == "first failure" and _G.calls == 1) or (scenario == "partial failure" and _G.calls == 2) then
        callback("injected failure")
        return
      end
      if scenario == "close" and _G.calls == 1 then
        args[slot] = function(err)
          _G.release = function() callback(err) end
        end
      end
      original(unpack(args))
    end
  ]],
      method,
      scenario,
      method,
      method == "delete" and 2 or 3
    )
  )
end

for _, entry in ipairs({ "write", "delete", "duplicate", "copy-paste", "cut-paste" }) do
  for _, scenario in ipairs({ "success", "first failure", "partial failure", "close" }) do
    T[entry .. " delivers one result after " .. scenario] = function()
      prepare(entry)
      inject(entry, scenario)
      local keys = ({ write = ":w<CR>", delete = "D", duplicate = "gd", ["copy-paste"] = "gp", ["cut-paste"] = "gp" })[entry]
      e2e.feed(child, keys)
      if scenario == "close" then
        e2e.wait_until(child, "_G.release ~= nil")
        e2e.exec(child, [[require("eda").close(); _G.release()]])
      end
      e2e.wait_until(child, "#_G.events >= 2")
      local events = e2e.exec(child, "return _G.events")
      MiniTest.expect.equality(#events, 2)
      MiniTest.expect.equality(events[1].name, "EdaMutationPre")
      MiniTest.expect.equality(events[2].name, "EdaMutationPost")
      local ops, result = events[1].data.operations, events[2].data.results
      MiniTest.expect.equality(#ops, 3)
      MiniTest.expect.equality(events[2].data.operations, ops)
      local count = scenario == "first failure" and 0 or (scenario == "partial failure" and 1 or 3)
      MiniTest.expect.equality(#result.completed, count)
      MiniTest.expect.equality(e2e.exec(child, "return _G.calls"), math.min(count + 1, 3))
      for i, op in ipairs(ops) do
        local completed = i <= count
        if completed then
          MiniTest.expect.equality(result.completed[i], op)
        end
        if entry == "write" then
          MiniTest.expect.equality(vim.fn.filereadable(op.path), completed and 1 or 0)
        elseif entry == "delete" then
          MiniTest.expect.equality(vim.fn.filereadable(op.path), completed and 0 or 1)
        else
          MiniTest.expect.equality(vim.fn.filereadable(op.dst), completed and 1 or 0)
          if completed then
            MiniTest.expect.equality(vim.fn.readfile(op.dst), { vim.fn.fnamemodify(op.src, ":t") })
          end
          MiniTest.expect.equality(vim.fn.filereadable(op.src), entry == "cut-paste" and completed and 0 or 1)
        end
      end
      if count < 3 then
        MiniTest.expect.equality(result.failed, ops[count + 1])
        MiniTest.expect.equality(result.error, "injected failure")
      else
        MiniTest.expect.equality(result.failed, nil)
        MiniTest.expect.equality(result.error, nil)
      end
      if entry == "copy-paste" or entry == "cut-paste" then
        local pending = {}
        for i = count + 1, #ops do
          pending[#pending + 1] = ops[i].src
        end
        MiniTest.expect.equality(
          e2e.exec(
            child,
            [[
          local reg = require("eda.register").get()
          return reg and reg.paths or {}
        ]]
          ),
          pending
        )
      elseif (entry == "delete" or entry == "duplicate") and scenario ~= "close" then
        local pending = {}
        for i = count + 1, #ops do
          pending[#pending + 1] = ops[i].src or ops[i].path
        end
        table.sort(pending)
        local marked = e2e.exec(
          child,
          [[
          local paths = {}
          for _, node in pairs(require("eda").get_current().store.nodes) do
            if node._marked then paths[#paths + 1] = node.path end
          end
          table.sort(paths)
          return paths
        ]]
        )
        MiniTest.expect.equality(marked, pending)
      end
      MiniTest.expect.equality(vim.fn.readfile(tmp .. "/dest/keep"), { "KEEP" })
    end
  end
end

for _, entry in ipairs({ "delete", "duplicate" }) do
  T[entry .. " completes without replacing unsaved buffer text"] = function()
    prepare(entry)
    e2e.feed(child, "Go")
    e2e.feed_insert(child, "pending_create")
    local lines = e2e.get_buf_lines(child)
    e2e.feed(child, entry == "delete" and "D" or "gd")
    e2e.wait_until(child, "#_G.events == 2")
    MiniTest.expect.equality(e2e.exec(child, "return #_G.events[2].data.results.completed"), 3)
    MiniTest.expect.equality(e2e.get_buf_lines(child), lines)
    MiniTest.expect.equality(e2e.exec(child, "return vim.bo.modified"), true)
    MiniTest.expect.equality(e2e.exec(child, [[return require("eda").get_current().refresh.pending]]), true)
    MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/pending_create"), 0)
  end
end

return T
