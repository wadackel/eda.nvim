vim.o.shadafile = "NONE"
io.write(string.format("E2E parent Neovim: %s (%s)\n", vim.v.progpath, tostring(vim.version())))

local mini_path = dofile("tests/bootstrap.lua").ensure()

vim.opt.runtimepath:prepend(mini_path)
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add tests/ to Lua package path so helpers can be required
-- E2E helpers are loaded via require("e2e.helpers") using tests/ as base
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. vim.fn.getcwd() .. "/tests/?/init.lua;" .. package.path

require("mini.test").setup()

MiniTest.run({
  collect = {
    find_files = function()
      return vim.fn.globpath("tests/e2e", "test_*.lua", false, true)
    end,
  },
})
