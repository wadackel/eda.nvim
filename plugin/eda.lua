if vim.g.loaded_eda then
  return
end
vim.g.loaded_eda = true

vim.api.nvim_create_user_command("Eda", function(args)
  local opts = {}
  for _, arg in ipairs(args.fargs) do
    local key, value = arg:match("^(%w+)=(.+)$")
    if key and value then
      opts[key] = value
    else
      opts.dir = arg
    end
  end
  require("eda").open(opts)
end, {
  nargs = "*",
  complete = "dir",
  desc = "Open eda file explorer",
})
