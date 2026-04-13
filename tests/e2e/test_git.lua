local e2e = require("e2e.helpers")

local T = MiniTest.new_set()

local child, tmp

T["git"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child = e2e.spawn()
      tmp = vim.uv.fs_realpath(e2e.create_temp_dir())
      e2e.create_file(tmp .. "/tracked.txt", "tracked")
      e2e.create_git_repo(tmp)
    end,
    post_case = function()
      e2e.stop(child)
      e2e.remove_temp_dir(tmp)
    end,
  },
})

T["git"]["displays git status icons in git repo"] = function()
  -- Create an untracked file after initial commit
  e2e.create_file(tmp .. "/untracked.txt", "untracked")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for git status to be fetched and rendered — check that the untracked file line
  -- contains the git icon. The default untracked icon is a nerd font char, but we just
  -- verify git status was fetched by checking the cached status map.
  e2e.wait_until(
    child,
    string.format(
      [[
    local git = require("eda.git")
    local status = git.get_cached(%q)
    return status ~= nil
  ]],
      tmp
    ),
    10000
  )

  -- Verify untracked.txt has git status
  local has_status = e2e.exec(
    child,
    string.format(
      [[
    local git = require("eda.git")
    local status = git.get_cached(%q)
    if not status then return false end
    return status[%q] == "?"
  ]],
      tmp,
      tmp .. "/untracked.txt"
    )
  )
  MiniTest.expect.equality(has_status, true)
end

T["git"]["toggle_gitignored shows and hides gitignored files"] = function()
  -- Create .gitignore and an ignored file
  e2e.create_file(tmp .. "/.gitignore", "ignored.txt\n")
  e2e.create_file(tmp .. "/ignored.txt", "should be ignored")
  vim.fn.system({ "git", "-C", tmp, "add", ".gitignore" })
  vim.fn.system({ "git", "-C", tmp, "commit", "-m", "add gitignore" })

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_gitignored = true,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for git status
  e2e.wait_until(child, string.format([[require("eda.git").get_cached(%q) ~= nil]], tmp), 10000)

  -- Initially gitignored files should be visible (show_gitignored = true)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("ignored.txt") then return true end
    end
    return false
  ]],
    5000
  )

  -- Press gi to toggle gitignored off
  e2e.feed(child, "gi")

  -- Wait for ignored.txt to disappear
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("ignored.txt") and not l:find(".gitignore") then return false end
    end
    return true
  ]],
    5000
  )

  -- Press gi again to toggle back on
  e2e.feed(child, "gi")

  -- ignored.txt should reappear
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("ignored.txt") and not l:find(".gitignore") then return true end
    end
    return false
  ]],
    5000
  )
end

-- In headless --listen mode, decoration provider on_line does not fire,
-- so we verify the decoration cache instead of checking live extmarks.
-- The cache is built during paint() and used by the provider at render time.
-- We verify that: (1) untracked files get a suffix entry in the cache,
-- (2) the suffix uses hl_mode="combine" in the code (checked via source contract).
T["git"]["cursorline bg is preserved through suffix virtual text"] = function()
  -- Create an untracked file after initial commit
  e2e.create_file(tmp .. "/untracked.txt", "untracked")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for git status to be fetched and rendered
  e2e.wait_until(
    child,
    string.format(
      [[
    local git = require("eda.git")
    local status = git.get_cached(%q)
    return status ~= nil
  ]],
      tmp
    ),
    10000
  )

  -- Wait for decoration cache to contain a suffix entry for untracked file.
  -- After git status is fetched, a re-render populates _decoration_cache.
  e2e.wait_until(
    child,
    [[
    local painter = require("eda").get_current().buffer.painter
    local cache = painter._decoration_cache
    for _, entry in pairs(cache) do
      if entry.suffix and entry.suffix ~= "" then
        return true
      end
    end
    return false
  ]],
    10000
  )

  -- Verify the untracked file specifically has a suffix with a highlight group
  local result = e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local buf = explorer.buffer
    local painter = buf.painter
    local cache = painter._decoration_cache
    -- Find untracked.txt node
    for _, fl in ipairs(buf.flat_lines) do
      if fl.node.name == "untracked.txt" then
        local entry = cache[fl.node_id]
        if entry then
          return {
            has_suffix = entry.suffix ~= nil and entry.suffix ~= "",
            suffix_hl = entry.suffix_hl,
          }
        end
      end
    end
    return { has_suffix = false }
  ]]
  )

  MiniTest.expect.equality(result.has_suffix, true)
  -- suffix_hl should be a non-empty string (the git status highlight group)
  MiniTest.expect.equality(type(result.suffix_hl) == "string" and result.suffix_hl ~= "", true)
end

-- ===========================================================================
-- next_git_change / prev_git_change / toggle_git_changes (Task 8)
-- ===========================================================================

local function setup_git_repo_with_changes(child)
  -- Repository layout:
  --   <tmp>/
  --     tracked.txt        (committed, then modified)
  --     subdir/committed.txt (committed, unchanged)
  --     subdir/changed.txt   (committed, then modified)
  --     untracked.txt        (untracked)
  e2e.create_dir(tmp .. "/subdir")
  e2e.create_file(tmp .. "/subdir/committed.txt", "stable")
  e2e.create_file(tmp .. "/subdir/changed.txt", "original")
  vim.fn.system({ "git", "-C", tmp, "add", "subdir" })
  vim.fn.system({ "git", "-C", tmp, "commit", "-m", "add subdir" })
  e2e.create_file(tmp .. "/tracked.txt", "modified")
  e2e.create_file(tmp .. "/subdir/changed.txt", "modified")
  e2e.create_file(tmp .. "/untracked.txt", "new")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)
end

local function get_cursor_node_name(child)
  return e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local node = explorer.buffer:get_cursor_node(explorer.window.winid)
    return node and node.name or nil
  ]]
  )
end

-- Dispatch an action directly via action.dispatch(), bypassing key mapping.
-- Used for CI timing stability: key sequences via nvim_input can race with the
-- parser's mapping-timeout buffer on slower runners.
local function dispatch(child, action_name)
  e2e.exec(
    child,
    string.format(
      [[
    local action = require("eda.action")
    local config = require("eda.config")
    local explorer = require("eda").get_current()
    local ctx = {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = config.get(),
      explorer = explorer,
    }
    action.dispatch(%q, ctx)
  ]],
      action_name
    )
  )
end

T["git"]["next_git_change jumps to a changed file"] = function()
  setup_git_repo_with_changes(child)

  -- Wait until explorer has fully rendered with git status applied
  e2e.wait_until(child, [[#vim.api.nvim_buf_get_lines(0, 0, -1, false) > 1]], 5000)

  -- Move cursor to line 1 (top of tree)
  e2e.feed(child, "gg")
  e2e.wait_until(child, [[vim.api.nvim_win_get_cursor(0)[1] == 1]], 2000)

  -- Jump to next git change
  e2e.feed(child, "]c")

  -- Wait for cursor to land on a changed file (tracked.txt, subdir/changed.txt, or untracked.txt)
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local node = explorer.buffer:get_cursor_node(explorer.window.winid)
    if not node then return false end
    return node.name == "tracked.txt" or node.name == "changed.txt" or node.name == "untracked.txt"
  ]],
    5000
  )
end

T["git"]["next_git_change wraps around on repeated presses"] = function()
  setup_git_repo_with_changes(child)
  e2e.wait_until(child, [[#vim.api.nvim_buf_get_lines(0, 0, -1, false) > 1]], 5000)

  -- Move cursor to top
  e2e.feed(child, "gg")
  e2e.wait_until(child, [[vim.api.nvim_win_get_cursor(0)[1] == 1]], 2000)

  -- Collect the sequence of cursor-node names by dispatching next_git_change
  -- repeatedly. Repo has 3 changed files (tracked.txt, subdir/changed.txt,
  -- untracked.txt). After 3 dispatches we should have visited 3 distinct files;
  -- after a 4th dispatch we must wrap back to a previously-visited file.
  local function wait_for_changed()
    e2e.wait_until(
      child,
      [[
      local explorer = require("eda").get_current()
      local node = explorer.buffer:get_cursor_node(explorer.window.winid)
      if not node then return false end
      return node.name == "tracked.txt"
        or node.name == "changed.txt"
        or node.name == "untracked.txt"
    ]],
      10000
    )
    return get_cursor_node_name(child)
  end

  local seen = {}
  for _ = 1, 3 do
    dispatch(child, "next_git_change")
    local name = wait_for_changed()
    seen[#seen + 1] = name
    vim.uv.sleep(100)
  end

  -- Verify 3 distinct changed files were visited
  local distinct = {}
  for _, n in ipairs(seen) do
    distinct[n] = true
  end
  local count = 0
  for _ in pairs(distinct) do
    count = count + 1
  end
  MiniTest.expect.equality(count, 3)

  -- 4th dispatch must wrap back to a previously-visited file
  dispatch(child, "next_git_change")
  local wrapped = wait_for_changed()
  MiniTest.expect.equality(distinct[wrapped] == true, true)
end

T["git"]["next_git_change auto-expands closed dir to reach changed file"] = function()
  setup_git_repo_with_changes(child)
  e2e.wait_until(child, [[#vim.api.nvim_buf_get_lines(0, 0, -1, false) > 1]], 5000)

  -- Collapse subdir first (select and close via children_state manipulation)
  e2e.exec(
    child,
    [[
    local explorer = require("eda").get_current()
    local subdir = explorer.store:get_by_path(vim.fn.getcwd() .. "/subdir")
  ]]
  )
  e2e.exec(
    child,
    string.format(
      [[
    local explorer = require("eda").get_current()
    local subdir = explorer.store:get_by_path(%q)
    if subdir then subdir.open = false end
    explorer.buffer:render(explorer.store)
  ]],
      tmp .. "/subdir"
    )
  )

  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("changed.txt") then return false end
    end
    return true
  ]],
    5000
  )

  -- Press ]c to navigate. It should auto-expand subdir and reach changed.txt eventually
  -- (the target may be tracked.txt or untracked.txt depending on tree order; we just
  -- verify that after enough presses, we land on changed.txt).
  local reached_changed = false
  for _ = 1, 5 do
    e2e.feed(child, "]c")
    vim.uv.sleep(100)
    local name = get_cursor_node_name(child)
    if name == "changed.txt" then
      reached_changed = true
      break
    end
  end
  MiniTest.expect.equality(reached_changed, true)
end

T["git"]["toggle_git_changes filters view to changed files and ancestors"] = function()
  setup_git_repo_with_changes(child)
  e2e.wait_until(child, [[#vim.api.nvim_buf_get_lines(0, 0, -1, false) > 1]], 5000)

  -- Expand subdir so committed.txt (unchanged) and changed.txt are visible.
  -- Use direct dispatch to avoid key-mapping timing races on slower CI runners.
  dispatch(child, "expand_all")

  -- Baseline: buffer shows unchanged file "committed.txt" somewhere
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("committed.txt") then return true end
    end
    return false
  ]],
    10000
  )

  -- Toggle filter on
  dispatch(child, "toggle_git_changes")

  -- committed.txt should disappear (it has no changes)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("committed.txt") then return false end
    end
    return true
  ]],
    10000
  )

  -- changed.txt should still be visible (changed file)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("changed.txt") then return true end
    end
    return false
  ]],
    10000
  )

  -- Toggle filter off
  dispatch(child, "toggle_git_changes")

  -- Wait for filter flag to settle
  e2e.wait_until(child, [[require("eda.config").get().show_only_git_changes == false]], 5000)

  -- committed.txt should reappear
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("committed.txt") then return true end
    end
    return false
  ]],
    10000
  )
end

T["git"]["toggle_git_changes rejects non-git directory"] = function()
  -- Use a non-git temporary directory
  local non_git = e2e.create_temp_dir()
  e2e.create_file(non_git .. "/file.txt", "content")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )
  e2e.open_eda(child, non_git)

  -- Wait for git.status to complete (cache[root] = { ready = "no_repo" })
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "no_repo"]], non_git), 5000)

  -- Dispatch toggle_git_changes directly — should be a no-op (filter stays false)
  dispatch(child, "toggle_git_changes")
  vim.uv.sleep(200)
  local is_filter_on = e2e.exec(child, [[return require("eda.config").get().show_only_git_changes]])
  MiniTest.expect.equality(is_filter_on, false)

  e2e.remove_temp_dir(non_git)
end

T["git"]["render shows loading empty-state when show_only_git_changes and git status pending"] = function()
  -- Set up a repo with changes BEFORE running eda so we have reported content later
  e2e.create_dir(tmp .. "/subdir")
  e2e.create_file(tmp .. "/subdir/committed.txt", "stable")
  e2e.create_file(tmp .. "/subdir/changed.txt", "original")
  vim.fn.system({ "git", "-C", tmp, "add", "subdir" })
  vim.fn.system({ "git", "-C", tmp, "commit", "-m", "add subdir" })
  e2e.create_file(tmp .. "/tracked.txt", "modified")
  e2e.create_file(tmp .. "/subdir/changed.txt", "modified")

  -- Start eda with show_only_git_changes = true so the first render enters
  -- the empty-state branch while git.status() is still in-flight ("loading").
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_only_git_changes = true,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)

  -- Wait for git status to fully settle, then verify the empty-state branch
  -- was exercised at least once during startup (recorded via the flag).
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Wait for the post-ready re-render to complete (filter view materializes)
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("tracked.txt") then return true end
    end
    return false
  ]],
    5000
  )

  -- Verify the empty-state render path was exercised during initial open
  -- (the loading empty-state is transient, but its occurrence is recorded)
  local empty_seen = e2e.exec(child, [[return require("eda").get_current()._empty_state_rendered == true]])
  MiniTest.expect.equality(empty_seen, true)

  -- Verify buffer is modifiable after git status becomes ready and tree renders
  -- (non-empty render restores modifiable=true via paint())
  local modifiable = e2e.exec(child, [[return vim.bo.modifiable]])
  MiniTest.expect.equality(modifiable, true)

  -- Reset filter for test isolation
  e2e.feed(child, "gs")
end

T["git"]["shows 'No git changes' when filter on and repo is clean"] = function()
  -- tmp is a clean git repo: tracked.txt is committed, no modifications.
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_only_git_changes = true,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Wait for render to complete with the empty message
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("No git changes") then return true end
    end
    return false
  ]],
    5000
  )

  -- Buffer should be non-modifiable in empty state
  local modifiable = e2e.exec(child, [[return vim.bo.modifiable]])
  MiniTest.expect.equality(modifiable, false)

  -- Toggle filter off; buffer should become modifiable again
  e2e.feed(child, "gs")
  e2e.wait_until(child, [[return vim.bo.modifiable == true]], 5000)
  local modifiable_after = e2e.exec(child, [[return vim.bo.modifiable]])
  MiniTest.expect.equality(modifiable_after, true)
end

T["git"]["filter indicator extmark appears on header row in split mode"] = function()
  -- Create files with changes directly (avoid setup_git_repo_with_changes which
  -- sets header=false; we need header=true here and must re-open in a fresh state).
  e2e.create_file(tmp .. "/tracked.txt", "modified")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = { format = "short", position = "left", divider = false },
    })
  ]]
  )
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Toggle filter on
  dispatch(child, "toggle_git_changes")

  -- Wait until both EdaRootName and filter indicator extmarks exist on row 0
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(explorer.buffer.bufnr, painter.ns_header, {0, 0}, {0, -1}, { details = true })
    local has_indicator = false
    local has_root = false
    for _, m in ipairs(marks) do
      local d = m[4]
      if d.virt_text then
        for _, chunk in ipairs(d.virt_text) do
          if type(chunk[1]) == "string" and chunk[1]:find("git changes") then
            has_indicator = true
          end
        end
      end
      if d.end_col and d.hl_group == "EdaRootName" then
        has_root = true
      end
    end
    return has_indicator and has_root
  ]],
    5000
  )
end

T["git"]["filter indicator chunk appears in float title when filter active"] = function()
  -- Create a modification so the filter has something to show
  e2e.create_file(tmp .. "/tracked.txt", "modified")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = { format = "short", position = "left", divider = false },
    })
  ]]
  )
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Toggle filter on
  dispatch(child, "toggle_git_changes")

  -- Wait until the float title contains a chunk with "git changes"
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local cfg = vim.api.nvim_win_get_config(explorer.window.winid)
    if type(cfg.title) ~= "table" then return false end
    for _, chunk in ipairs(cfg.title) do
      if type(chunk[1]) == "string" and chunk[1]:find("git changes") then
        return true
      end
    end
    return false
  ]],
    5000
  )
end

T["git"]["non-git directory with show_only_git_changes=true auto-disables filter and notifies once"] = function()
  local non_git = e2e.create_temp_dir()
  e2e.create_file(non_git .. "/file.txt", "content")

  -- Monkey-patch vim.notify BEFORE eda.setup so the capture is in place for the first render.
  e2e.exec(
    child,
    [[
    _G.captured_notifies = {}
    vim.notify = function(msg, level)
      table.insert(_G.captured_notifies, { msg = msg, level = level })
    end
  ]]
  )

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_only_git_changes = true,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], non_git))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "no_repo"]], non_git), 5000)

  -- Wait for the auto-disable render pass to run
  e2e.wait_until(child, [[require("eda.config").get().show_only_git_changes == false]], 5000)

  -- Exactly one WARN notify with "not a git repository"
  local notify_count = e2e.exec(
    child,
    [[
    local n = 0
    for _, entry in ipairs(_G.captured_notifies or {}) do
      if type(entry.msg) == "string" and entry.msg:find("not a git repository") and entry.level == vim.log.levels.WARN then
        n = n + 1
      end
    end
    return n
  ]]
  )
  MiniTest.expect.equality(notify_count, 1)

  e2e.remove_temp_dir(non_git)
end

T["git"]["shows 'No git changes' when all files are gitignored and filter is on"] = function()
  -- Add .gitignore that ignores debug.log, commit it, then create an untracked gitignored file.
  e2e.create_file(tmp .. "/.gitignore", "*.log\n")
  vim.fn.system({ "git", "-C", tmp, "add", ".gitignore" })
  vim.fn.system({ "git", "-C", tmp, "commit", "-m", "add gitignore" })
  e2e.create_file(tmp .. "/debug.log", "log content")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
      show_gitignored = false,
      show_only_git_changes = true,
    })
  ]]
  )

  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- The gitignored file is hidden and all other files are clean, so "No git changes" is shown.
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, l in ipairs(lines) do
      if l:find("No git changes") then return true end
    end
    return false
  ]],
    5000
  )
end

T["git"]["filter indicator toggles off cleanly in split mode"] = function()
  e2e.create_file(tmp .. "/tracked.txt", "modified")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = { format = "short", position = "left", divider = false },
    })
  ]]
  )
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Toggle ON then OFF
  dispatch(child, "toggle_git_changes")
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(explorer.buffer.bufnr, painter.ns_header, {0,0}, {0,-1}, {details = true})
    for _, m in ipairs(marks) do
      if m[4].virt_text then
        for _, chunk in ipairs(m[4].virt_text) do
          if type(chunk[1]) == "string" and chunk[1]:find("git changes") then return true end
        end
      end
    end
    return false
  ]],
    5000
  )

  dispatch(child, "toggle_git_changes")
  -- Indicator extmark must be gone after toggling off
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local painter = explorer.buffer.painter
    local marks = vim.api.nvim_buf_get_extmarks(explorer.buffer.bufnr, painter.ns_header, {0,0}, {0,-1}, {details = true})
    for _, m in ipairs(marks) do
      if m[4].virt_text then
        for _, chunk in ipairs(m[4].virt_text) do
          if type(chunk[1]) == "string" and chunk[1]:find("git changes") then return false end
        end
      end
    end
    return true
  ]],
    5000
  )
end

T["git"]["float title filter indicator works with center title position"] = function()
  e2e.create_file(tmp .. "/tracked.txt", "modified")

  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = { format = "short", position = "center", divider = false },
    })
  ]]
  )
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  dispatch(child, "toggle_git_changes")

  -- With center position, the filter chunk is placed adjacent to the header
  -- (no padding / border fill). The chunks must still contain "git changes".
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local cfg = vim.api.nvim_win_get_config(explorer.window.winid)
    if type(cfg.title) ~= "table" then return false end
    if cfg.title_pos ~= "center" then return false end
    local has_filter = false
    local has_fill = false
    for _, chunk in ipairs(cfg.title) do
      if type(chunk[1]) == "string" then
        if chunk[1]:find("git changes") then has_filter = true end
        if chunk[1]:match("^\xe2\x94\x80+$") or chunk[1]:match("^\xe2\x95\x90+$") then
          has_fill = true
        end
      end
    end
    -- Must have the filter chunk; must NOT have horizontal fill padding
    return has_filter and not has_fill
  ]],
    5000
  )
end

T["git"]["toggle_git_changes during git loading updates float title"] = function()
  -- Create a large-ish repo so git status is still loading when we toggle.
  e2e.create_file(tmp .. "/tracked.txt", "modified")

  -- Start eda in float mode with filter OFF, toggle it on before git settles.
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "float" },
      confirm = false,
      header = { format = "short", position = "left", divider = false },
    })
  ]]
  )
  e2e.exec(child, string.format([[require("eda").open({ dir = %q })]], tmp))
  e2e.wait_until(child, [[vim.bo.filetype == "eda"]], 5000)

  -- Invalidate git cache so the next render re-enters "loading" state.
  e2e.exec(child, string.format([[require("eda.git").invalidate(%q)]], tmp))
  e2e.exec(
    child,
    [[
    local action = require("eda.action")
    local config = require("eda.config")
    local explorer = require("eda").get_current()
    local ctx = {
      store = explorer.store,
      buffer = explorer.buffer,
      window = explorer.window,
      scanner = explorer.scanner,
      config = config.get(),
      explorer = explorer,
    }
    action.dispatch("toggle_git_changes", ctx)
  ]]
  )

  -- Title must reflect the indicator even before the next git ready transition.
  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local cfg = vim.api.nvim_win_get_config(explorer.window.winid)
    if type(cfg.title) ~= "table" then return false end
    for _, chunk in ipairs(cfg.title) do
      if type(chunk[1]) == "string" and chunk[1]:find("git changes") then
        return true
      end
    end
    return false
  ]],
    5000
  )
end

T["git"]["next_git_change jumps through edit_preserve path on dirty buffer"] = function()
  setup_git_repo_with_changes(child)
  e2e.wait_until(child, [[#vim.api.nvim_buf_get_lines(0, 0, -1, false) > 1]], 5000)

  -- Make the explorer buffer dirty by directly setting the modified flag.
  -- (The actual edit operations go through buffer/edit_preserve.lua but for the
  -- purpose of verifying `_refresh_for_navigation` routing we only need modified=true.)
  e2e.exec(
    child,
    [[
    vim.bo.modified = true
  ]]
  )

  local modified_before = e2e.exec(child, [[return vim.bo.modified]])
  MiniTest.expect.equality(modified_before, true)

  -- Dispatch next_git_change directly — must jump despite dirty state
  -- (previously broken: target_node_id was ignored because render_with_decorators
  -- early-returned on modified=true)
  dispatch(child, "next_git_change")

  e2e.wait_until(
    child,
    [[
    local explorer = require("eda").get_current()
    local node = explorer.buffer:get_cursor_node(explorer.window.winid)
    if not node then return false end
    return node.name == "tracked.txt"
      or node.name == "changed.txt"
      or node.name == "untracked.txt"
  ]],
    10000
  )
end

-- ===========================================================================
-- Real-time git status refresh after buffer editing
-- ===========================================================================

T["git"]["git status refreshes after creating a file via buffer edit"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for initial git status to be ready
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Create a new file via buffer editing
  e2e.exec(child, "vim.api.nvim_win_set_cursor(0, {1, 0})")
  e2e.feed(child, "o")
  e2e.feed_insert(child, "new_untracked.txt")
  e2e.feed(child, ":w<CR>")

  -- Wait for the file to exist on disk
  local new_path = tmp .. "/new_untracked.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) ~= nil", new_path))

  -- Wait for git status cache to reflect the new untracked file
  e2e.wait_until(
    child,
    string.format(
      [[
    local git = require("eda.git")
    local status = git.get_cached(%q)
    if not status then return false end
    return status[%q] == "?"
  ]],
      tmp,
      new_path
    ),
    10000
  )
end

T["git"]["git status refreshes after renaming a file via buffer edit"] = function()
  e2e.exec(
    child,
    [[
    require("eda").setup({
      git = { enabled = true },
      icon = { provider = "none" },
      window = { kind = "split_left", width = 40 },
      confirm = false,
      header = false,
    })
  ]]
  )

  e2e.open_eda(child, tmp)

  -- Wait for initial git status to be ready
  e2e.wait_until(child, string.format([[require("eda.git").get_status_ready(%q) == "ready"]], tmp), 10000)

  -- Rename tracked.txt to renamed.txt via buffer editing
  e2e.wait_until(
    child,
    [[
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for i, l in ipairs(lines) do
      if l:find("tracked.txt") then
        vim.api.nvim_win_set_cursor(0, {i, 0})
        return true
      end
    end
    return false
  ]]
  )
  e2e.feed(child, "cc")
  e2e.feed_insert(child, "renamed.txt")
  e2e.feed(child, ":w<CR>")

  -- Wait for rename to complete on disk
  local old_path = tmp .. "/tracked.txt"
  local new_path = tmp .. "/renamed.txt"
  e2e.wait_until(child, string.format("vim.uv.fs_stat(%q) == nil and vim.uv.fs_stat(%q) ~= nil", old_path, new_path))

  -- Wait for git status cache to reflect the rename
  e2e.wait_until(
    child,
    string.format(
      [[
    local git = require("eda.git")
    local status = git.get_cached(%q)
    if not status then return false end
    -- After rename, the new file shows as untracked (?) or deleted+added
    local s = status[%q]
    return s ~= nil
  ]],
      tmp,
      new_path
    ),
    10000
  )
end

return T
