local M = {}

function M.check()
  vim.health.start("eda.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok("Neovim >= 0.11")
  else
    vim.health.error("Neovim >= 0.11 is required")
  end

  -- Git
  if vim.fn.executable("git") == 1 then
    vim.health.ok("git found")
  else
    vim.health.warn("git not found (git integration will be disabled)")
  end

  -- Icon provider
  local cfg = require("eda.config").get()
  local icon_provider = cfg.icon and cfg.icon.provider or "mini_icons"
  if icon_provider == "none" then
    vim.health.ok("Icon provider disabled")
  else
    local mod_name = icon_provider == "mini_icons" and "mini.icons" or "nvim-web-devicons"
    if pcall(require, mod_name) then
      vim.health.ok(mod_name .. " available")
    else
      vim.health.warn(mod_name .. ' not found (install it or set icon.provider = "none")')
    end
  end

  -- Registered actions
  local action = require("eda.action")
  local names = action.list()
  vim.health.ok(string.format("%d actions registered", #names))
end

return M
