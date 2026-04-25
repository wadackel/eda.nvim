local helpers = require("helpers")

local M = {}

local plugin_root = vim.fn.getcwd()

---Spawn a child Neovim instance for E2E testing via MiniTest.new_child_neovim().
---@return table child object from MiniTest.new_child_neovim()
function M.spawn()
  local child = MiniTest.new_child_neovim()
  child.start()
  -- Add eda.nvim to runtimepath
  child.lua("vim.opt.rtp:prepend(...)", { plugin_root })
  return child
end

---Stop a child Neovim instance.
---@param child table child object from MiniTest.new_child_neovim()
function M.stop(child)
  child.stop()
end

---Execute Lua code in the child Neovim and return the result.
---@param child table child object from MiniTest.new_child_neovim()
---@param code string Lua code to execute (use `return` to get a value back)
---@return any
function M.exec(child, code)
  return child.lua(code)
end

---Send keys to the child Neovim via nvim_input (does not check v:errmsg).
---@param child table child object from MiniTest.new_child_neovim()
---@param keys string Key sequence (e.g. "<CR>", "dd", ":w<CR>")
function M.feed(child, keys)
  child.api.nvim_input(keys)
end

---Type text and return to normal mode, waiting for mode transition.
---@param child table child object from MiniTest.new_child_neovim()
---@param text string Text to type in insert mode
function M.feed_insert(child, text)
  child.api.nvim_input(text)
  child.api.nvim_input("<Esc>")
  M.wait_until(child, 'vim.api.nvim_get_mode().mode == "n"')
end

---Poll the child Neovim until a Lua predicate returns truthy.
---Uses vim.uv.sleep() instead of vim.wait() to avoid pumping the parent event loop.
---Default timeout is 10000ms: e2e tests must absorb spikes from a heavily loaded
---runner (Ubuntu GHA, parallel local runs) where the scan + paint chain can
---legitimately exceed 5s. Per-call sites that need a tighter ceiling can pass
---an explicit timeout_ms.
---@param child table child object from MiniTest.new_child_neovim()
---@param predicate_lua string Lua expression evaluated in the child Neovim
---@param timeout_ms? integer Maximum wait time (default 10000)
---@param interval_ms? integer Poll interval (default 50)
function M.wait_until(child, predicate_lua, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 10000
  interval_ms = interval_ms or 50
  local deadline = vim.uv.hrtime() + timeout_ms * 1e6

  -- Wrap predicate in a function to handle both single-expression and multi-statement predicates.
  -- Single expressions (e.g. 'vim.bo.filetype == "eda"') need an added return.
  -- Multi-statement blocks already contain their own return statements.
  local has_return = predicate_lua:find("return%s") ~= nil
  local wrapped
  if has_return then
    wrapped = "return (function() " .. predicate_lua .. " end)()"
  else
    wrapped = "return (" .. predicate_lua .. ")"
  end

  while vim.uv.hrtime() < deadline do
    local ok, result = pcall(child.lua, wrapped)
    if ok and result then
      return
    end
    if not ok then
      local err_str = tostring(result)
      -- Lua evaluation errors should fail immediately (not retry)
      if err_str:find("Error executing lua") then
        error("wait_until predicate error: " .. err_str, 2)
      end
      -- RPC transport errors -> retry
    end
    vim.uv.sleep(interval_ms)
  end
  error("wait_until timed out after " .. timeout_ms .. "ms waiting for: " .. predicate_lua, 2)
end

---Get all lines from the current buffer in the child Neovim.
---@param child table child object from MiniTest.new_child_neovim()
---@return string[]
function M.get_buf_lines(child)
  return child.api.nvim_buf_get_lines(0, 0, -1, false)
end

---Setup eda.nvim in the child Neovim with E2E test defaults.
---@param child table child object from MiniTest.new_child_neovim()
function M.setup_eda(child)
  M.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = false },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )
end

---Open the eda explorer in the child Neovim and wait for it to be ready.
---@param child table child object from MiniTest.new_child_neovim()
---@param dir string Root directory to open
function M.open_eda(child, dir)
  M.exec(child, string.format([[require("eda").open({ dir = %q })]], dir))
  -- Wait for filetype to be set and for at least one non-empty line (scan + render complete)
  M.wait_until(
    child,
    [[
    vim.bo.filetype == "eda"
    and vim.api.nvim_buf_line_count(0) > 0
    and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ~= ""
  ]]
  )
end

---Get the window count in the child Neovim.
---@param child table child object from MiniTest.new_child_neovim()
---@return integer
function M.get_win_count(child)
  return M.exec(child, "return #vim.api.nvim_list_wins()")
end

---Get the tab count in the child Neovim.
---@param child table child object from MiniTest.new_child_neovim()
---@return integer
function M.get_tab_count(child)
  return M.exec(child, "return #vim.api.nvim_list_tabpages()")
end

---Wait until the node at `path` has been scanned (children_state == "loaded").
---Source of truth: lua/eda/tree/scanner.lua sets "loaded" on completion.
---@param child table child object from MiniTest.new_child_neovim()
---@param path string Absolute path of the node to wait for
---@param timeout_ms? integer Maximum wait time (default 5000)
function M.wait_for_node_loaded(child, path, timeout_ms)
  M.wait_until(
    child,
    string.format(
      [[
    local ok, eda = pcall(require, "eda")
    if not ok then return false end
    local explorer = eda.get_current()
    if not explorer then return false end
    local node = explorer.store:get_by_path(%q)
    return node ~= nil and node.children_state == "loaded"
  ]],
      path
    ),
    timeout_ms
  )
end

---Wait until a node with the given path is rendered (present in painter snapshot).
---Source of truth: lua/eda/render/painter.lua:get_snapshot returns
---{ entries = { [node_id] = { line, path } } }.
---@param child table child object from MiniTest.new_child_neovim()
---@param path string Absolute path of the rendered node to wait for
---@param timeout_ms? integer Maximum wait time (default 5000)
function M.wait_for_path_in_snapshot(child, path, timeout_ms)
  M.wait_until(
    child,
    string.format(
      [[
    local ok, eda = pcall(require, "eda")
    if not ok then return false end
    local explorer = eda.get_current()
    if not (explorer and explorer.buffer and explorer.buffer.painter) then return false end
    local snap = explorer.buffer.painter:get_snapshot()
    for _, entry in pairs(snap.entries or {}) do
      if entry.path == %q then return true end
    end
    return false
  ]],
      path
    ),
    timeout_ms
  )
end

---Press `<CR>` (the default eda `select` mapping) and wait for the full
---edit-preserve render cycle (paint + optional replay) to complete. Driven
---by the `User EdaRenderComplete` event fired in lua/eda/init.lua at the
---tail of `render_preserving_edits`. Uses a persistent counter rather than a
---one-shot autocmd: a stray event that fires between `arm` and `<CR>` still
---bumps the counter, but the wait_until requires the counter to advance from
---the snapshot taken AFTER `<CR>` is queued, so the dispatch we care about is
---always observed.
---@param child table child object from MiniTest.new_child_neovim()
function M.expand_and_wait_for_render(child)
  M.exec(
    child,
    [[
    if not vim.g._eda_test_render_count_setup then
      vim.g._eda_test_render_count = 0
      vim.api.nvim_create_autocmd("User", {
        pattern = "EdaRenderComplete",
        callback = function()
          vim.g._eda_test_render_count = (vim.g._eda_test_render_count or 0) + 1
        end,
      })
      vim.g._eda_test_render_count_setup = true
    end
  ]]
  )
  local before = M.exec(child, "return vim.g._eda_test_render_count or 0")
  M.feed(child, "<CR>")
  M.wait_until(child, string.format("vim.g._eda_test_render_count > %d", before))
end

---Set up a one-shot User autocmd that flips vim.g[flag_var] to true on fire.
---Caller invokes BEFORE dispatching the trigger action, then waits with
---wait_until(child, "vim.g[flag_var] == true") AFTER the dispatch.
---event must match a fire_event site in lua/eda/init.lua, e.g. EdaTreeOpen,
---EdaRootChanged, EdaTreeClose, EdaMutationPre, EdaMutationPost.
---@param child table child object from MiniTest.new_child_neovim()
---@param event string User autocmd pattern (e.g. "EdaRootChanged")
---@param flag_var string Name of the vim.g key used as the completion flag
function M.arm_user_event(child, event, flag_var)
  M.exec(
    child,
    string.format(
      [[
    vim.g[%q] = false
    vim.api.nvim_create_autocmd("User", {
      pattern = %q,
      once = true,
      callback = function() vim.g[%q] = true end,
    })
  ]],
      flag_var,
      event,
      flag_var
    )
  )
end

---Initialize a git repository in the given directory.
---@param dir string
function M.create_git_repo(dir)
  vim.fn.system({ "git", "init", dir })
  -- Set local identity so commits succeed on runners without a global git identity
  vim.fn.system({ "git", "-C", dir, "config", "user.email", "test@test.com" })
  vim.fn.system({ "git", "-C", dir, "config", "user.name", "Test" })
  vim.fn.system({ "git", "-C", dir, "add", "." })
  vim.fn.system({ "git", "-C", dir, "commit", "-m", "init", "--allow-empty" })
end

-- Re-export helpers for temp dir management
M.create_temp_dir = helpers.create_temp_dir
M.create_file = helpers.create_file
M.create_dir = helpers.create_dir
M.remove_temp_dir = helpers.remove_temp_dir

return M
