local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

---Count windows whose buffer has filetype == "eda_inspect" in the child Neovim.
---@param child_ table
---@return integer
local function inspect_win_count(child_)
  return e2e.exec(
    child_,
    [[
    return (function()
      local n = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          n = n + 1
        end
      end
      return n
    end)()
  ]]
  )
end

T["cold open race"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/foo.txt", "hello")
      e2e.create_dir(tmp .. "/bar")
      -- setup only; DO NOT open_eda (it waits for initial render which masks the race)
      e2e.setup_eda(child)
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

-- Regression: when the user presses the mapped inspect key in the same event
-- tick as the explorer open (cold start), the initial scan is still in flight
-- and `flat_lines` is empty. Previously the dispatch hit `get_cursor_node` ==
-- nil and silently returned via the "no target at cursor" notify. After the
-- fix, dispatches issued before initial render are parked and drained once
-- the render completes, so the inspect float eventually opens.
T["cold open race"]["A: <Leader>i pressed in the same tick as open still opens inspect"] = function()
  -- Sanity: nothing open before.
  MiniTest.expect.equality(inspect_win_count(child), 0)

  -- Feed open + leader-i in a single child-side Lua call so they land in the
  -- same event tick (no sleep/schedule between them).
  e2e.exec(
    child,
    string.format(
      [[
      require("eda").open({ dir = %q })
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Leader>i", true, false, true), "mtx", false)
      return true
    ]],
      tmp
    )
  )

  -- With the fix in place: pending dispatch is drained on initial scan
  -- completion, inspect float opens eventually (within poll deadline).
  -- Without the fix: poll times out, inspect_win_count stays 0.
  e2e.wait_until(
    child,
    [[
    return (function()
      local n = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          n = n + 1
        end
      end
      return n == 1
    end)()
  ]]
  )

  MiniTest.expect.equality(inspect_win_count(child), 1)
end

-- Regression: the same race also applies when the root changes on an already-
-- open explorer (parent/cwd/cd actions go through `_change_root`). Pressing a
-- mapped action key in the same tick as the root change used to hit the same
-- empty-`flat_lines` gap until `_change_root` was taught to reset and drain
-- the pending-dispatch slot.
T["cold open race"]["B: <Leader>i pressed in the same tick as root change still opens inspect"] = function()
  -- Open first, wait for initial render so we isolate the root-change path.
  e2e.open_eda(child, tmp)
  MiniTest.expect.equality(inspect_win_count(child), 0)

  -- Close any pre-existing inspect float (none expected) and feed parent + leader-i
  -- in a single event tick: `^` dispatches the `parent` action which triggers
  -- `_change_root` (async scan), and `<Leader>i` immediately follows.
  e2e.exec(
    child,
    [[
      local ks = vim.api.nvim_replace_termcodes("^<Leader>i", true, false, true)
      vim.api.nvim_feedkeys(ks, "mtx", false)
      return true
    ]]
  )

  e2e.wait_until(
    child,
    [[
    return (function()
      local n = 0
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype == "eda_inspect" then
          n = n + 1
        end
      end
      return n == 1
    end)()
  ]]
  )

  MiniTest.expect.equality(inspect_win_count(child), 1)
end

return T
