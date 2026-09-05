local bootstrap = dofile("tests/bootstrap.lua")
local helpers = require("helpers")
local tmp, source, revision, newer, options, original_system, original_rename

local function git(path, ...)
  local result = vim.system({ "git", "-C", path, ... }, { text = true }):wait(10000)
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function cache_path()
  return options.root .. "/mini.nvim-" .. revision
end

local function expect_error(fn, pattern)
  local ok, err = pcall(fn)
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(tostring(err):find(pattern, 1, true) ~= nil, true)
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      original_system, original_rename = vim.system, vim.uv.fs_rename
      tmp = helpers.create_temp_dir()
      source = tmp .. "/source"
      helpers.create_file(source .. "/lua/mini/test.lua", "return { fixture = true }\n")
      git(source, "init", "--quiet")
      git(source, "config", "user.name", "Test")
      git(source, "config", "user.email", "test@example.com")
      git(source, "config", "commit.gpgsign", "false")
      git(source, "add", ".")
      git(source, "commit", "--quiet", "-m", "fixture")
      revision = git(source, "rev-parse", "HEAD")
      helpers.create_file(source .. "/newer", "new commit")
      git(source, "add", ".")
      git(source, "commit", "--quiet", "-m", "newer fixture")
      newer = git(source, "rev-parse", "HEAD")
      options = { root = tmp .. "/cache", repository = source, revision = revision }
    end,
    post_case = function()
      vim.system, vim.uv.fs_rename = original_system, original_rename
      helpers.remove_temp_dir(tmp)
    end,
  },
})

T["fresh bootstrap checks out the requested commit rather than remote HEAD"] = function()
  local path = bootstrap.ensure(options)
  MiniTest.expect.equality(path, cache_path())
  MiniTest.expect.equality(git(path, "rev-parse", "HEAD"), revision)
  MiniTest.expect.equality(vim.fn.readfile(path .. "/lua/mini/test.lua"), { "return { fixture = true }" })
  MiniTest.expect.equality(vim.uv.fs_stat(path .. "/newer"), nil)
  MiniTest.expect.equality(vim.fn.readdir(options.root), { "mini.nvim-" .. revision })
end

T["matching cache works without contacting the repository"] = function()
  local path = bootstrap.ensure(options)
  options.repository = tmp .. "/offline"
  MiniTest.expect.equality(bootstrap.ensure(options), path)
  MiniTest.expect.equality(git(path, "rev-parse", "HEAD"), revision)
end

T["mismatched cache is rejected without resetting its checkout"] = function()
  local path = bootstrap.ensure(options)
  git(path, "fetch", "--quiet", source, newer)
  git(path, "checkout", "--quiet", "--detach", newer)
  expect_error(function()
    bootstrap.ensure(options)
  end, "expected " .. revision)
  MiniTest.expect.equality(git(path, "rev-parse", "HEAD"), newer)
  MiniTest.expect.equality(vim.fn.readfile(path .. "/newer"), { "new commit" })
end

for _, filename in ipairs({ "lua/mini/test.lua", "untracked.lua" }) do
  T["dirty cache preserves local changes to " .. filename] = function()
    local path = bootstrap.ensure(options)
    helpers.create_file(path .. "/" .. filename, "KEEP LOCAL CHANGES")
    expect_error(function()
      bootstrap.ensure(options)
    end, "working tree")
    MiniTest.expect.equality(vim.fn.readfile(path .. "/" .. filename), { "KEEP LOCAL CHANGES" })
  end
end

T["incomplete cache is rejected without deleting unrelated data"] = function()
  helpers.create_file(cache_path() .. "/keep", "KEEP")
  expect_error(function()
    bootstrap.ensure(options)
  end, "cache")
  MiniTest.expect.equality(vim.fn.readfile(cache_path() .. "/keep"), { "KEEP" })
end

T["missing entrypoint is rejected even when HEAD matches"] = function()
  local path = bootstrap.ensure(options)
  assert(vim.uv.fs_unlink(path .. "/lua/mini/test.lua"))
  expect_error(function()
    bootstrap.ensure(options)
  end, "lua/mini/test.lua")
  MiniTest.expect.equality(git(path, "rev-parse", "HEAD"), revision)
end

T["fetch failure names the operation and cleans its staging directory"] = function()
  options.repository = tmp .. "/missing-repository"
  expect_error(function()
    bootstrap.ensure(options)
  end, "fetch")
  MiniTest.expect.equality(vim.fn.readdir(options.root), {})
end

T["checkout failure cannot publish an initialized but incomplete repository"] = function()
  vim.system = function(command, opts)
    if command[4] == "checkout" then
      return {
        wait = function()
          return { code = 1, stderr = "injected checkout failure" }
        end,
      }
    end
    return original_system(command, opts)
  end
  expect_error(function()
    bootstrap.ensure(options)
  end, "checkout")
  MiniTest.expect.equality(vim.fn.readdir(options.root), {})
end

T["spawn failure names the attempted Git operation"] = function()
  vim.system = function()
    error("injected executable unavailable")
  end
  expect_error(function()
    bootstrap.ensure(options)
  end, "init")
  MiniTest.expect.equality(vim.fn.readdir(options.root), {})
end

T["a blocked cache root is reported without changing the blocking file"] = function()
  helpers.create_file(options.root, "KEEP")
  expect_error(function()
    bootstrap.ensure(options)
  end, "cache root")
  MiniTest.expect.equality(vim.fn.readfile(options.root), { "KEEP" })
end

T["publication failure leaves no final or staging checkout"] = function()
  vim.uv.fs_rename = function()
    return nil, "injected publication failure"
  end
  expect_error(function()
    bootstrap.ensure(options)
  end, "cannot publish checkout")
  MiniTest.expect.equality(vim.fn.readdir(options.root), {})
end

T["an invalid destination appearing during checkout is preserved"] = function()
  vim.system = function(command, opts)
    if command[4] == "checkout" then
      helpers.create_file(cache_path() .. "/keep", "KEEP")
    end
    return original_system(command, opts)
  end
  expect_error(function()
    bootstrap.ensure(options)
  end, "cache")
  MiniTest.expect.equality(vim.fn.readfile(cache_path() .. "/keep"), { "KEEP" })
  MiniTest.expect.equality(vim.fn.readdir(options.root), { "mini.nvim-" .. revision })
end

T["concurrent fresh processes publish one complete checkout"] = function()
  local processes = {}
  for index = 1, 2 do
    local script = tmp .. "/bootstrap-" .. index .. ".lua"
    helpers.create_file(
      script,
      string.format(
        [[
local system, rename = vim.system, vim.uv.fs_rename
local function barrier(stage)
  vim.fn.writefile({}, %q .. stage)
  assert(vim.wait(10000, function() return vim.uv.fs_stat(%q .. stage) ~= nil end, 10))
end
vim.system = function(command, opts)
  if command[4] == "fetch" then barrier("fetch") end
  return system(command, opts)
end
vim.uv.fs_rename = function(src, dst)
  barrier("publish")
  return rename(src, dst)
end
local path = dofile("tests/bootstrap.lua").ensure(%s)
print(path)
vim.cmd("qa!")
]],
        tmp .. "/ready-" .. index,
        tmp .. "/ready-" .. (3 - index),
        vim.inspect(options)
      )
    )
    processes[index] = original_system({ vim.v.progpath, "--clean", "--headless", "-l", script }, { text = true })
  end
  local results = { processes[1]:wait(20000), processes[2]:wait(20000) }
  for _, result in ipairs(results) do
    assert(result.code == 0, results[1].stderr .. "\n" .. results[2].stderr)
  end
  MiniTest.expect.equality(git(cache_path(), "rev-parse", "HEAD"), revision)
  MiniTest.expect.equality(vim.fn.readdir(options.root), { "mini.nvim-" .. revision })
  MiniTest.expect.equality(bootstrap.ensure(options), cache_path())
end

for _, runner in ipairs({ "tests/minit.lua", "tests/e2e_minit.lua" }) do
  T[runner .. " exits before collection when its cache is invalid"] = function()
    local data = tmp .. "/data"
    local cache = data .. "/nvim/eda-test-deps/mini.nvim-" .. bootstrap.revision
    helpers.create_file(cache .. "/keep", "KEEP")
    local result = original_system(
      { vim.v.progpath, "--clean", "--headless", "-l", runner },
      { text = true, env = { XDG_DATA_HOME = data } }
    ):wait(20000)
    MiniTest.expect.equality(result.code ~= 0, true)
    MiniTest.expect.equality(result.stderr:find("cache", 1, true) ~= nil, true)
    MiniTest.expect.equality(result.stdout:find("Total number of cases", 1, true), nil)
    MiniTest.expect.equality(vim.fn.readfile(cache .. "/keep"), { "KEEP" })
  end
end

return T
