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

  -- Image preview
  if vim.fn.executable("magick") == 1 then
    vim.health.ok("magick found (JPEG/GIF/WebP/BMP previews are converted to PNG)")
  else
    vim.health.info(
      "magick not found (PNG files up to 2048px on a side are previewed as-is; other formats need ImageMagick)"
    )
  end
  if vim.env.TMUX then
    vim.health.info("running inside tmux (allow-passthrough is enabled for the pane on first image preview)")
  end
  local image_cfg = type(cfg.preview) == "table" and cfg.preview.image
  if type(image_cfg) == "table" and image_cfg.enabled then
    local remediation = 'set preview.image.transmission = "direct" if the preview stays blank'
    if image_cfg.transmission == "direct" then
      vim.health.info("image transmission: direct (configured)")
    elseif image_cfg.transmission == "file" then
      vim.health.info("image transmission: file path (configured); " .. remediation)
    elseif require("eda.image.terminal").is_remote() then
      vim.health.info("image transmission: direct (SSH session detected)")
    else
      vim.health.info("image transmission: file path (t=f); " .. remediation)
    end
  end

  -- Registered actions
  local action = require("eda.action")
  local names = action.list()
  vim.health.ok(string.format("%d actions registered", #names))
end

return M
