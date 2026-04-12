local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h:h")
local data_dir = "/tmp/eda-screenshot-deps"

local function ensure_repo(url, dest)
  if vim.fn.isdirectory(dest) == 0 then
    vim.fn.system({ "git", "clone", "--depth=1", url, dest })
  else
    vim.fn.system({ "git", "-C", dest, "pull", "--ff-only" })
  end
end

ensure_repo("https://github.com/wadackel/vim-dogrun", data_dir .. "/vim-dogrun")
ensure_repo("https://github.com/echasnovski/mini.icons", data_dir .. "/mini.icons")

vim.opt.rtp:prepend(data_dir .. "/vim-dogrun")
vim.opt.rtp:prepend(data_dir .. "/mini.icons")
vim.opt.rtp:prepend(root)

vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.termguicolors = true
vim.o.number = false
vim.o.relativenumber = false
vim.o.signcolumn = "no"
vim.o.laststatus = 0
vim.o.cmdheight = 1
vim.o.showmode = false
vim.o.ruler = false
vim.o.showcmd = false
vim.cmd.colorscheme("dogrun")
require("mini.icons").setup()

local kind = vim.env.EDA_SCREENSHOT_KIND or "float"
local git_enabled = vim.env.EDA_SCREENSHOT_GIT == "1"
local target_dir = vim.env.EDA_SCREENSHOT_DIR or "/tmp/eda-screenshot-project"

require("eda").setup({
  window = { kind = kind },
  git = { enabled = git_enabled },
  show_hidden = false,
  expand_depth = 5,
  header = { format = "minimal", position = "left", divider = true },
})

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    require("eda").open({ dir = target_dir })
  end,
})
