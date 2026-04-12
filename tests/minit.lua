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

MiniTest.run({
  collect = {
    find_files = function()
      return vim.tbl_filter(function(f)
        return not f:find("e2e/")
      end, vim.fn.globpath("tests", "**/test_*.lua", false, true))
    end,
  },
})
