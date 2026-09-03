vim.o.shadafile = "NONE"

-- Bootstrap mini.nvim for testing
local deps_path = vim.fn.stdpath("data") .. "/eda-test-deps"
local mini_path = deps_path .. "/mini.nvim"

if not vim.uv.fs_stat(mini_path) then
  vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/echasnovski/mini.nvim", mini_path })
end

vim.opt.runtimepath:prepend(mini_path)
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add tests/ to Lua package path so helpers can be required
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path

require("mini.test").setup()

local cases = MiniTest.collect({
  find_files = function()
    return vim.tbl_filter(function(f)
      return not f:find("e2e/")
    end, vim.fn.globpath("tests", "**/test_*.lua", false, true))
  end,
})

-- MiniTest.run() schedules every case up front, so a `vim.wait` inside one case
-- processes the queue and runs the remaining cases (and the final `qa!`) nested
-- inside it: a case whose wait times out is abandoned and reported as passing.
-- Executing one case at a time keeps each case's event loop to its own work.
local silent = {
  start = function() end,
  update = function() end,
  finish = function() end,
}

io.write(string.format("Total number of cases: %d\n", #cases))

local fails, notes = {}, {}
local current_file
for _, case in ipairs(cases) do
  local file = case.desc[1]
  if file ~= current_file then
    if current_file then
      io.write("\n")
    end
    io.write(file .. ": ")
    current_file = file
  end

  MiniTest.execute({ case }, { reporter = silent })
  vim.wait(300000, function()
    return not MiniTest.is_executing()
  end, 10)

  local name = table.concat(case.desc, " | ")
  for _, fail in ipairs(case.exec.fails) do
    fails[#fails + 1] = name .. ":\n  " .. fail:gsub("\n", "\n  ")
  end
  for _, note in ipairs(case.exec.notes) do
    notes[#notes + 1] = name .. ": " .. note
  end
  io.write(#case.exec.fails > 0 and "x" or "o")
end
io.write("\n\n")

io.write(string.format("Fails (%d) and Notes (%d)\n", #fails, #notes))
for _, fail in ipairs(fails) do
  io.write("\nFAIL in " .. fail .. "\n")
end
for _, note in ipairs(notes) do
  io.write("\nNOTE in " .. note .. "\n")
end
io.flush()

if #fails > 0 then
  vim.cmd("cquit 1")
end
vim.cmd("qa!")
