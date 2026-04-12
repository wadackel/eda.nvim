vim.o.shadafile = "NONE"

-- Bootstrap mini.nvim for E2E testing
local deps_path = vim.fn.stdpath("data") .. "/eda-test-deps"
local mini_path = deps_path .. "/mini.nvim"

if not vim.uv.fs_stat(mini_path) then
  vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/echasnovski/mini.nvim", mini_path })
end

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
