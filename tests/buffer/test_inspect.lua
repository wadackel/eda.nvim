local Inspect = require("eda.buffer.inspect")
local helpers = require("helpers")

local T = MiniTest.new_set()

---Helper to find the inspect float window.
---@return integer? win_id
---@return integer? buf_id
local function find_inspect_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "eda_inspect" then
      return win, buf
    end
  end
  return nil, nil
end

---Build a minimal mock stat result.
local function mock_lstat(overrides)
  local base = {
    size = 2048,
    -- 0o100644 = regular file bits (0o100000) + 0o644 perms
    mode = 33188,
    uid = 501,
    gid = 20,
    mtime = { sec = 1710066662 }, -- 2024-03-10 ...
    atime = { sec = 1713443430 },
    birthtime = { sec = 1701355425 },
    type = "file",
  }
  if overrides then
    for k, v in pairs(overrides) do
      base[k] = v
    end
  end
  return base
end

-- ===== format_size (returns main, muted|nil) =====

T["format_size formats bytes under 1 KiB (muted nil)"] = function()
  local main, muted = Inspect._format_size(0)
  MiniTest.expect.equality(main, "0 B")
  MiniTest.expect.equality(muted, nil)
  main, muted = Inspect._format_size(512)
  MiniTest.expect.equality(main, "512 B")
  MiniTest.expect.equality(muted, nil)
  main, muted = Inspect._format_size(1023)
  MiniTest.expect.equality(main, "1023 B")
  MiniTest.expect.equality(muted, nil)
end

T["format_size formats bytes at or above 1 KiB with muted absolute count"] = function()
  local main, muted = Inspect._format_size(1024)
  MiniTest.expect.equality(main, "1.00 KiB")
  MiniTest.expect.equality(muted, "(1,024 bytes)")
  main, muted = Inspect._format_size(1234567)
  MiniTest.expect.equality(main, "1.18 MiB")
  MiniTest.expect.equality(muted, "(1,234,567 bytes)")
end

T["format_size handles nil / negative"] = function()
  local main, muted = Inspect._format_size(nil)
  MiniTest.expect.equality(main, "(unavailable)")
  MiniTest.expect.equality(muted, nil)
  main, muted = Inspect._format_size(-1)
  MiniTest.expect.equality(main, "(unavailable)")
  MiniTest.expect.equality(muted, nil)
end

-- ===== format_mode (returns main, muted|nil) =====

T["format_mode renders 0o755 with muted octal"] = function()
  local main, muted = Inspect._format_mode(493, "d") -- 0o755
  MiniTest.expect.equality(main, "drwxr-xr-x")
  MiniTest.expect.equality(muted, "(0o755)")
end

T["format_mode renders 0o644 with muted octal"] = function()
  local main, muted = Inspect._format_mode(420, "-") -- 0o644
  MiniTest.expect.equality(main, "-rw-r--r--")
  MiniTest.expect.equality(muted, "(0o644)")
end

T["format_mode strips file-type bits from stat.mode"] = function()
  local main, muted = Inspect._format_mode(33188, "-") -- 0o100644
  MiniTest.expect.equality(main, "-rw-r--r--")
  MiniTest.expect.equality(muted, "(0o644)")
end

T["format_mode renders sticky bit as t when other-x is set"] = function()
  local main, muted = Inspect._format_mode(1023, "d") -- 0o1777
  MiniTest.expect.equality(main, "drwxrwxrwt")
  MiniTest.expect.equality(muted, "(0o1777)")
end

T["format_mode renders sticky bit as T when other-x is unset"] = function()
  local main, muted = Inspect._format_mode(1016, "d") -- 0o1770
  MiniTest.expect.equality(main, "drwxrwx--T")
  MiniTest.expect.equality(muted, "(0o1770)")
end

T["format_mode renders setuid as s when user-x is set"] = function()
  local main, muted = Inspect._format_mode(2541, "-") -- 0o4755
  MiniTest.expect.equality(main, "-rwsr-xr-x")
  MiniTest.expect.equality(muted, "(0o4755)")
end

T["format_mode renders setuid as S when user-x is unset"] = function()
  local main, muted = Inspect._format_mode(2468, "-") -- 0o4644
  MiniTest.expect.equality(main, "-rwSr--r--")
  MiniTest.expect.equality(muted, "(0o4644)")
end

T["format_mode renders setgid as s when group-x is set"] = function()
  local main, muted = Inspect._format_mode(1517, "-") -- 0o2755
  MiniTest.expect.equality(main, "-rwxr-sr-x")
  MiniTest.expect.equality(muted, "(0o2755)")
end

T["format_mode handles nil"] = function()
  local main, muted = Inspect._format_mode(nil, "-")
  MiniTest.expect.equality(main, "(unavailable)")
  MiniTest.expect.equality(muted, nil)
end

-- ===== format_time =====

T["format_time formats ISO 8601 local"] = function()
  local result = Inspect._format_time(1710066662)
  MiniTest.expect.equality(result:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$") ~= nil, true)
end

T["format_time returns (unavailable) for nil or 0"] = function()
  MiniTest.expect.equality(Inspect._format_time(nil), "(unavailable)")
  MiniTest.expect.equality(Inspect._format_time(0), "(unavailable)")
end

-- ===== format_relative_time =====

T["format_relative_time nil / 0 returns nil"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(nil, 1000), nil)
  MiniTest.expect.equality(Inspect._format_relative_time(0, 1000), nil)
end

T["format_relative_time under 60 seconds is just now"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1000, 1000), "(just now)")
  MiniTest.expect.equality(Inspect._format_relative_time(1000, 1059), "(just now)")
end

T["format_relative_time clamps future timestamps to just now"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(2000, 1000), "(just now)")
end

T["format_relative_time under 1 hour reports minutes with plural"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1, 61), "(~1 minute)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 121), "(~2 minutes)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 3600), "(~59 minutes)")
end

T["format_relative_time under 1 day reports hours with plural"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1, 3601), "(~1 hour)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 7201), "(~2 hours)")
end

T["format_relative_time under 30 days reports days with plural"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400), "(~1 day)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400 * 5), "(~5 days)")
end

T["format_relative_time under 365 days reports months with plural"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400 * 30), "(~1 month)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400 * 90), "(~3 months)")
end

T["format_relative_time 365 days or more reports years with plural"] = function()
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400 * 365), "(~1 year)")
  MiniTest.expect.equality(Inspect._format_relative_time(1, 1 + 86400 * 365 * 4), "(~4 years)")
end

-- ===== build_lines =====

---Helper: count lines that exactly match / start with a header-style pattern.
local function lines_matching(build, pattern)
  local count = 0
  for _, line in ipairs(build.lines) do
    if line:find(pattern) then
      count = count + 1
    end
  end
  return count
end

---Helper: return the set of hl groups used across all extmarks.
local function hl_groups_used(build)
  local seen = {}
  for _, mark in ipairs(build.extmarks) do
    seen[mark.hl] = true
  end
  return seen
end

---Fixed `now` so tests are deterministic. mock_lstat mtime is 1710066662
---(Mar 2024); picking now = 1710066662 + 7200 makes it ~2 hours ago.
local FIXED_NOW = 1710066662 + 7200

T["build_lines has no section headers for file"] = function()
  local node = { name = "foo.txt", path = "/tmp/foo.txt", type = "file", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat(), mock_lstat(), nil, "/tmp", FIXED_NOW)
  -- None of the removed headers should appear anywhere in the output.
  MiniTest.expect.equality(lines_matching(build, "^General"), 0)
  MiniTest.expect.equality(lines_matching(build, "^Timestamps"), 0)
  MiniTest.expect.equality(lines_matching(build, "^Symlink"), 0)
  MiniTest.expect.equality(lines_matching(build, "^Directory"), 0)
  -- Key-value content is still present.
  MiniTest.expect.equality(lines_matching(build, "Path"), 1)
  MiniTest.expect.equality(lines_matching(build, "Size") > 0, true)
  MiniTest.expect.equality(lines_matching(build, "Modified"), 1)
end

T["build_lines uses only EdaInspect* hl groups"] = function()
  local node = { name = "foo.txt", path = "/tmp/foo.txt", type = "file", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat(), mock_lstat(), nil, "/tmp", FIXED_NOW)
  local seen = hl_groups_used(build)
  -- Expected groups.
  MiniTest.expect.equality(seen["EdaInspectLabel"] == true, true)
  MiniTest.expect.equality(seen["EdaInspectValue"] == true, true)
  MiniTest.expect.equality(seen["EdaInspectValueMuted"] == true, true)
  -- Built-in groups must not leak through.
  for _, banned in ipairs({ "Special", "Normal", "Comment", "Directory", "DiagnosticError" }) do
    MiniTest.expect.equality(seen[banned], nil)
  end
end

T["build_lines appends relative time to each timestamp row"] = function()
  local node = { name = "foo.txt", path = "/tmp/foo.txt", type = "file", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat(), mock_lstat(), nil, "/tmp", FIXED_NOW)
  local modified_line
  for _, line in ipairs(build.lines) do
    if line:find("Modified") then
      modified_line = line
    end
  end
  MiniTest.expect.no_equality(modified_line, nil)
  -- FIXED_NOW - mtime(1710066662) = 7200s → (~2 hours)
  MiniTest.expect.equality(modified_line:find("%(~2 hours%)") ~= nil, true)
end

T["build_lines shows Size '-' for directory"] = function()
  local node = { name = "dir", path = "/tmp/dir", type = "directory", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat({ type = "directory" }), mock_lstat({ type = "directory" }), {
    total = 5,
    file = 3,
    directory = 1,
    link = 1,
    other = 0,
  }, "/tmp", FIXED_NOW)
  local size_line
  for _, line in ipairs(build.lines) do
    if line:find("Size") then
      size_line = line
    end
  end
  MiniTest.expect.no_equality(size_line, nil)
  MiniTest.expect.equality(size_line:find("%-%s*$") ~= nil, true)
end

T["build_lines Entries row splits main count and muted breakdown"] = function()
  local node = { name = "dir", path = "/tmp/dir", type = "directory", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat({ type = "directory" }), mock_lstat({ type = "directory" }), {
    total = 5,
    file = 3,
    directory = 1,
    link = 1,
    other = 0,
  }, "/tmp", FIXED_NOW)
  -- No "Directory" header row.
  MiniTest.expect.equality(lines_matching(build, "^Directory"), 0)
  local entries_line
  for _, line in ipairs(build.lines) do
    if line:find("Entries") then
      entries_line = line
    end
  end
  MiniTest.expect.no_equality(entries_line, nil)
  MiniTest.expect.equality(entries_line:find("5") ~= nil, true)
  MiniTest.expect.equality(entries_line:find("%(3 files, 1 dirs, 1 links%)") ~= nil, true)
end

T["build_lines surfaces directory scan error via EdaInspectError"] = function()
  local node = { name = "dir", path = "/tmp/dir", type = "directory", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat({ type = "directory" }), mock_lstat({ type = "directory" }), {
    error = "permission denied",
  }, "/tmp", FIXED_NOW)
  local has_error = false
  for _, line in ipairs(build.lines) do
    if line:find("permission denied") then
      has_error = true
    end
  end
  MiniTest.expect.equality(has_error, true)
  local seen = hl_groups_used(build)
  MiniTest.expect.equality(seen["EdaInspectError"] == true, true)
end

T["build_lines exposes symlink Target without a Symlink header"] = function()
  local node = {
    name = "sample.link",
    path = "/tmp/sample.link",
    type = "link",
    link_target = "/tmp/sample.txt",
    link_broken = false,
  }
  local build = Inspect._build_lines(node, mock_lstat({ type = "link" }), mock_lstat(), nil, "/tmp", FIXED_NOW)
  MiniTest.expect.equality(lines_matching(build, "^Symlink"), 0)
  local has_target = false
  for _, line in ipairs(build.lines) do
    if line:find("/tmp/sample.txt") then
      has_target = true
    end
  end
  MiniTest.expect.equality(has_target, true)
end

T["build_lines shows 'broken' for broken symlink via EdaInspectError"] = function()
  local node = {
    name = "dangling.link",
    path = "/tmp/dangling.link",
    type = "link",
    link_target = "/tmp/missing",
    link_broken = true,
  }
  local build = Inspect._build_lines(node, mock_lstat({ type = "link" }), nil, nil, "/tmp", FIXED_NOW)
  local has_broken = false
  for _, line in ipairs(build.lines) do
    if line:find("broken") then
      has_broken = true
    end
  end
  MiniTest.expect.equality(has_broken, true)
  local seen = hl_groups_used(build)
  MiniTest.expect.equality(seen["EdaInspectError"] == true, true)
end

T["build_lines shows error via EdaInspectError when lstat is nil"] = function()
  local node = { name = "gone", path = "/tmp/gone", type = "file", link_broken = false }
  local build = Inspect._build_lines(node, nil, nil, nil, "/tmp", FIXED_NOW)
  local has_error = false
  for _, line in ipairs(build.lines) do
    if line:find("Error") or line:find("stat") then
      has_error = true
    end
  end
  MiniTest.expect.equality(has_error, true)
  local seen = hl_groups_used(build)
  MiniTest.expect.equality(seen["EdaInspectError"] == true, true)
end

T["build_lines uses relative path when inside root"] = function()
  local node = { name = "sub.txt", path = "/tmp/root/sub.txt", type = "file", link_broken = false }
  local build = Inspect._build_lines(node, mock_lstat(), mock_lstat(), nil, "/tmp/root", FIXED_NOW)
  local path_line
  for _, line in ipairs(build.lines) do
    if line:find("Path") then
      path_line = line
    end
  end
  MiniTest.expect.no_equality(path_line, nil)
  MiniTest.expect.equality(path_line:find("sub%.txt") ~= nil, true)
  MiniTest.expect.equality(path_line:find("/tmp/root/") ~= nil, false)
end

-- ===== compute_inspect_layout =====

T["compute_inspect_layout returns required float config fields (cursor-anchored, no title)"] = function()
  local build = { lines = { "General", "  Path  /tmp/foo.txt" }, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 40, columns = 120, cmdheight = 1, screen_row = 5 })
  MiniTest.expect.equality(layout.relative, "cursor")
  MiniTest.expect.equality(layout.style, "minimal")
  MiniTest.expect.equality(layout.border, "rounded")
  MiniTest.expect.equality(layout.zindex, 52)
  -- Title row is intentionally omitted (less visual noise for an auxiliary float).
  MiniTest.expect.equality(layout.title, nil)
  MiniTest.expect.equality(layout.title_pos, nil)
  MiniTest.expect.equality(layout.footer, " <leader>i: close ")
  MiniTest.expect.equality(layout.footer_pos, "center")
  MiniTest.expect.equality(layout.col, 0)
  MiniTest.expect.equality(type(layout.width), "number")
  MiniTest.expect.equality(type(layout.height), "number")
  MiniTest.expect.equality(type(layout.row), "number")
  MiniTest.expect.equality(type(layout.anchor), "string")
end

T["compute_inspect_layout enforces minimum width of 40"] = function()
  local build = { lines = { "x" }, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 40, columns = 200, cmdheight = 1, screen_row = 5 })
  MiniTest.expect.equality(layout.width >= 40, true)
end

T["compute_inspect_layout caps height to 25"] = function()
  local many_lines = {}
  for i = 1, 50 do
    many_lines[i] = "line " .. i
  end
  local build = { lines = many_lines, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 80, columns = 120, cmdheight = 1, screen_row = 5 })
  MiniTest.expect.equality(layout.height, 25)
end

T["compute_inspect_layout places float below cursor when room permits (NW/row=1)"] = function()
  local build = { lines = { "a", "b", "c" }, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 40, columns = 120, cmdheight = 1, screen_row = 5 })
  MiniTest.expect.equality(layout.anchor, "NW")
  MiniTest.expect.equality(layout.row, 1)
  MiniTest.expect.equality(layout.col, 0)
end

T["compute_inspect_layout flips above cursor when no room below (SW/row=0)"] = function()
  local build = { lines = { "a", "b", "c" }, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 40, columns = 120, cmdheight = 1, screen_row = 39 })
  MiniTest.expect.equality(layout.anchor, "SW")
  MiniTest.expect.equality(layout.row, 0)
  MiniTest.expect.equality(layout.col, 0)
end

T["compute_inspect_layout flips when cmdheight shrinks available space"] = function()
  local build = { lines = { "a", "b", "c" }, extmarks = {} }
  local layout = Inspect._compute_inspect_layout(build, { lines = 40, columns = 120, cmdheight = 20, screen_row = 25 })
  MiniTest.expect.equality(layout.anchor, "SW")
  MiniTest.expect.equality(layout.row, 0)
end

-- ===== scan_direct_children =====

T["scan_direct_children counts direct entries"] = function()
  local tmp = helpers.create_temp_dir()
  helpers.create_file(tmp .. "/a.txt")
  helpers.create_file(tmp .. "/b.txt")
  helpers.create_dir(tmp .. "/sub")
  local counts = Inspect._scan_direct_children(tmp)
  MiniTest.expect.equality(counts.total, 3)
  MiniTest.expect.equality(counts.file, 2)
  MiniTest.expect.equality(counts.directory, 1)
  MiniTest.expect.equality(counts.link, 0)
  helpers.remove_temp_dir(tmp)
end

T["scan_direct_children does not recurse"] = function()
  local tmp = helpers.create_temp_dir()
  helpers.create_file(tmp .. "/a.txt")
  helpers.create_dir(tmp .. "/sub")
  helpers.create_file(tmp .. "/sub/nested.txt")
  local counts = Inspect._scan_direct_children(tmp)
  MiniTest.expect.equality(counts.total, 2)
  MiniTest.expect.equality(counts.file, 1)
  MiniTest.expect.equality(counts.directory, 1)
  helpers.remove_temp_dir(tmp)
end

T["scan_direct_children returns error for nonexistent path"] = function()
  local counts = Inspect._scan_direct_children("/tmp/does-not-exist-" .. vim.uv.hrtime())
  MiniTest.expect.no_equality(counts.error, nil)
end

-- ===== float lifecycle =====

local function mock_ctx()
  -- Minimal ctx that show()/close() need: no window, no store → falls back to editor
  return {
    window = { winid = nil },
    store = nil,
  }
end

T["show creates float window with filetype eda_inspect"] = function()
  Inspect.close() -- clean slate
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hello")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node)

  local win, buf = find_inspect_window()
  MiniTest.expect.no_equality(win, nil)
  MiniTest.expect.no_equality(buf, nil)
  MiniTest.expect.equality(vim.bo[buf].filetype, "eda_inspect")
  MiniTest.expect.equality(vim.bo[buf].modifiable, false)
  MiniTest.expect.equality(vim.bo[buf].buftype, "nofile")

  Inspect.close()
  helpers.remove_temp_dir(tmp)
end

T["close removes the float window"] = function()
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  Inspect.close()
  MiniTest.expect.equality(Inspect.is_visible(), false)
  local win, _ = find_inspect_window()
  MiniTest.expect.equality(win, nil)

  helpers.remove_temp_dir(tmp)
end

T["toggle opens when hidden and closes when visible"] = function()
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.close()
  MiniTest.expect.equality(Inspect.is_visible(), false)

  Inspect.toggle(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  Inspect.toggle(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), false)

  helpers.remove_temp_dir(tmp)
end

T["show sets window highlights"] = function()
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node)
  local win, _ = find_inspect_window()
  MiniTest.expect.no_equality(win, nil)
  local winhl = vim.wo[win].winhl
  MiniTest.expect.equality(winhl:find("FloatBorder:EdaInspectBorder") ~= nil, true)
  MiniTest.expect.equality(winhl:find("FloatFooter:EdaInspectFooter") ~= nil, true)
  -- Title row removed; no EdaInspectTitle highlight expected.
  MiniTest.expect.equality(winhl:find("EdaInspectTitle") == nil, true)

  Inspect.close()
  helpers.remove_temp_dir(tmp)
end

T["update swaps content to a different node while keeping the float visible"] = function()
  local tmp = helpers.create_temp_dir()
  local file_a = tmp .. "/a.txt"
  local file_b = tmp .. "/b.txt"
  helpers.create_file(file_a, "hi")
  helpers.create_file(file_b, string.rep("y", 2048))
  local node_a = { name = "a.txt", path = file_a, type = "file", link_broken = false }
  local node_b = { name = "b.txt", path = file_b, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node_a)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  Inspect.update(mock_ctx(), node_b)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  local _, buf = find_inspect_window()
  assert(buf, "inspect buffer not found")
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  MiniTest.expect.equality(text:find("b%.txt") ~= nil, true)
  MiniTest.expect.equality(text:find("a%.txt") ~= nil, false)

  Inspect.close()
  helpers.remove_temp_dir(tmp)
end

T["update closes the float when node is nil"] = function()
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  Inspect.update(mock_ctx(), nil)
  MiniTest.expect.equality(Inspect.is_visible(), false)

  helpers.remove_temp_dir(tmp)
end

T["update is a no-op when the float is not visible"] = function()
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.close()
  MiniTest.expect.equality(Inspect.is_visible(), false)

  -- Should not raise, should not open a new float.
  Inspect.update(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), false)

  helpers.remove_temp_dir(tmp)
end

T["close keymap q closes the inspect float when focused"] = function()
  -- Safety-net behavior: focus normally stays in the explorer, but if the user
  -- deliberately focuses the float (e.g. <C-w>w), pressing q must still close it.
  local tmp = helpers.create_temp_dir()
  local file = tmp .. "/foo.txt"
  helpers.create_file(file, "hi")
  local node = { name = "foo.txt", path = file, type = "file", link_broken = false }

  Inspect.show(mock_ctx(), node)
  MiniTest.expect.equality(Inspect.is_visible(), true)

  local win = find_inspect_window()
  assert(win, "inspect window not found")
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_feedkeys("q", "x", false)

  MiniTest.expect.equality(Inspect.is_visible(), false)
  helpers.remove_temp_dir(tmp)
end

return T
