local Diff = require("eda.tree.diff")
local Store = require("eda.tree.store")
local Fs = require("eda.fs")
local helpers = require("helpers")

local tmp

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      tmp = helpers.create_temp_dir()
    end,
    post_case = function()
      helpers.remove_temp_dir(tmp)
    end,
  },
})

local function batch(files, changes)
  local store = Store.new()
  local root = store:set_root(tmp)
  local snapshot, parsed = { entries = {} }, {}
  for i, file in ipairs(files) do
    local name, contents = file[1], file[2]
    local path = tmp .. "/" .. name
    if contents == false then
      vim.fn.mkdir(path, "p")
    else
      helpers.create_file(path, contents)
    end
    local parent = store:get_by_path(vim.fn.fnamemodify(path, ":h"))
    local id = store:add({
      name = name,
      path = path,
      parent_id = parent and parent.id or root,
      type = contents == false and "directory" or "file",
    })
    snapshot.entries[id] = { line = i - 1, path = path }
    if changes[name] ~= false then
      parsed[#parsed + 1] =
        { node_id = id, full_path = tmp .. "/" .. (changes[name] or name), is_dir = contents == false }
    end
  end
  return Diff.compute(parsed, snapshot, store), store
end

local function run_if_valid(ops, store)
  local validation = Diff.validate(ops, store)
  if not validation.valid then
    return validation
  end
  local result
  Fs.execute_operations(ops, { delete_to_trash = false }, function(value)
    result = value
  end)
  helpers.wait_for(5000, function()
    return result ~= nil
  end)
  MiniTest.expect.equality(result.error, nil)
  return validation
end

T["rejects a swap before either source changes"] = function()
  local ops, store = batch({ { "a", "A" }, { "b", "B" } }, { a = "b", b = "a" })
  MiniTest.expect.equality(run_if_valid(ops, store).valid, false)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/b"), { "B" })
end

T["rejects a moved destination also scheduled for deletion"] = function()
  local ops, store = batch({ { "a", "A" }, { "b", "B" } }, { a = "b", b = false })
  MiniTest.expect.equality(run_if_valid(ops, store).valid, false)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/b"), { "B" })
end

T["renames an expanded directory without redundant descendant moves"] = function()
  local ops, store = batch(
    { { "src", false }, { "src/a", "A" }, { "src/deep", false }, { "src/deep/b", "B" } },
    { src = "lib", ["src/a"] = "lib/a", ["src/deep"] = "lib/deep", ["src/deep/b"] = "lib/deep/b" }
  )
  MiniTest.expect.equality(#ops, 1)
  MiniTest.expect.equality(run_if_valid(ops, store).valid, true)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/lib/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/lib/deep/b"), { "B" })
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/src"), nil)
end

T["rejects explicit descendant edits alongside a parent move"] = function()
  local ops, store = batch({ { "src", false }, { "src/a", "A" } }, { src = "lib", ["src/a"] = "lib/renamed" })
  MiniTest.expect.equality(run_if_valid(ops, store).valid, false)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/src/a"), { "A" })
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/lib"), nil)
end

T["extracts a child before deleting its directory"] = function()
  local ops, store = batch({ { "src", false }, { "src/a", "A" } }, { src = false, ["src/a"] = "a" })
  MiniTest.expect.equality(run_if_valid(ops, store).valid, true)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/a"), { "A" })
  MiniTest.expect.equality(vim.uv.fs_stat(tmp .. "/src"), nil)
end

T["keeps sibling path prefixes independent"] = function()
  local ops, store = batch(
    { { "src", false }, { "src/a", "A" }, { "src-extra", "B" } },
    { src = "lib", ["src/a"] = "lib/a", ["src-extra"] = "other" }
  )
  MiniTest.expect.equality(run_if_valid(ops, store).valid, true)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/lib/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/other"), { "B" })
end

T["detects ancestor conflicts even with intervening sibling prefixes"] = function()
  local ops, store = batch(
    { { "src", false }, { "src/a", "A" }, { "src-extra", "B" } },
    { src = "lib", ["src/a"] = false, ["src-extra"] = "other" }
  )
  MiniTest.expect.equality(run_if_valid(ops, store).valid, false)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/src/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/src-extra"), { "B" })
end

T["detects move dependencies through symlinked parents"] = function()
  local ops, store = batch(
    { { "real", false }, { "real/a", "A" }, { "real/b", "B" } },
    { ["real/a"] = "alias/b", ["real/b"] = "real/c" }
  )
  assert(vim.uv.fs_symlink(tmp .. "/real", tmp .. "/alias"))
  MiniTest.expect.equality(run_if_valid(ops, store).valid, false)
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/real/a"), { "A" })
  MiniTest.expect.equality(vim.fn.readfile(tmp .. "/real/b"), { "B" })
end

T["creates parent directories before independent children"] = function()
  local store = Store.new()
  store:set_root(tmp)
  local ops = Diff.compute({
    { name = "new", full_path = tmp .. "/new", is_dir = true },
    { name = "file", full_path = tmp .. "/new/file", is_dir = false },
  }, { entries = {} }, store)
  MiniTest.expect.equality(run_if_valid(ops, store).valid, true)
  MiniTest.expect.equality(vim.fn.filereadable(tmp .. "/new/file"), 1)
end

return T
