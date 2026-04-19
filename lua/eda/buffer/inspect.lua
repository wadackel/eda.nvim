local util = require("eda.util")

local M = {}

---@class eda.InspectState
---@field winid integer
---@field bufnr integer
---@field node_path string

---@type eda.InspectState?
local _state = nil

local _ns_hl = vim.api.nvim_create_namespace("eda_inspect_hl")

-- ========== Pure helpers ==========

---Insert thousands separators into a non-negative integer.
---@param n integer
---@return string
local function format_int(n)
  local s = tostring(n)
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

---Human-readable size plus a muted absolute byte count.
---Returns (main, muted|nil). For sizes under 1 KiB the muted component is nil
---(the human-readable form already shows the exact byte count).
---@param bytes integer?
---@return string main
---@return string? muted
local function format_size(bytes)
  if not bytes or bytes < 0 then
    return "(unavailable)", nil
  end
  if bytes < 1024 then
    return string.format("%d B", bytes), nil
  end
  local units = { "B", "KiB", "MiB", "GiB", "TiB" }
  local idx, n = 1, bytes
  while n >= 1024 and idx < #units do
    n = n / 1024
    idx = idx + 1
  end
  return string.format("%.2f %s", n, units[idx]), string.format("(%s bytes)", format_int(bytes))
end

---Render the 9 permission bits of a stat.mode, prefixed with a type char,
---plus a muted octal representation.
---Returns (main, muted|nil).
---@param mode integer? vim.uv.fs_stat().mode (may include file type bits)
---@param type_char string "d" | "l" | "-" (or other single char)
---@return string main
---@return string? muted
local function format_mode(mode, type_char)
  if not mode then
    return "(unavailable)", nil
  end
  local perm_bits = mode % 4096 -- strip file-type bits, keep 0o7777 (suid/sgid/sticky + rwx)
  -- Bit-test without the `bit` library: bit `mask` is set when (n mod (mask*2)) >= mask
  local function has(mask)
    return (perm_bits % (mask * 2)) >= mask
  end
  -- Render exec bits with suid/sgid/sticky semantics (ls -l convention):
  --   exec + special bit => lowercase (s/s/t); special bit alone => uppercase (S/S/T).
  local function exec_char(exec_mask, special_mask, lower_s)
    local e, s = has(exec_mask), has(special_mask)
    if s and e then
      return lower_s
    elseif s then
      return lower_s:upper()
    elseif e then
      return "x"
    end
    return "-"
  end
  local chars = {
    has(256) and "r" or "-", -- 0o400 user read
    has(128) and "w" or "-", -- 0o200 user write
    exec_char(64, 2048, "s"), -- 0o100 + 0o4000 suid
    has(32) and "r" or "-", -- 0o040 group read
    has(16) and "w" or "-", -- 0o020 group write
    exec_char(8, 1024, "s"), -- 0o010 + 0o2000 sgid
    has(4) and "r" or "-", -- 0o004 other read
    has(2) and "w" or "-", -- 0o002 other write
    exec_char(1, 512, "t"), -- 0o001 + 0o1000 sticky
  }
  return string.format("%s%s", type_char or "-", table.concat(chars)), string.format("(0o%o)", perm_bits)
end

---ISO 8601 local datetime (YYYY-MM-DD HH:MM:SS) or "(unavailable)".
---@param sec integer? epoch seconds
---@return string
local function format_time(sec)
  if not sec or sec == 0 then
    return "(unavailable)"
  end
  ---@diagnostic disable-next-line: return-type-mismatch
  return os.date("%Y-%m-%d %H:%M:%S", sec)
end

---Human-readable relative-time hint: "(just now)" / "(~N unit[s])".
---Returns nil when the timestamp is unavailable, so callers can skip the
---muted suffix entirely in that case. Future timestamps (e.g. clock skew)
---clamp to "(just now)".
---@param sec integer? epoch seconds
---@param now integer epoch seconds representing the "current" time (injected for tests)
---@return string?
local function format_relative_time(sec, now)
  if not sec or sec == 0 then
    return nil
  end
  local diff = now - sec
  if diff < 0 then
    diff = 0
  end
  if diff < 60 then
    return "(just now)"
  end
  local n, unit
  if diff < 3600 then
    n, unit = math.floor(diff / 60), "minute"
  elseif diff < 86400 then
    n, unit = math.floor(diff / 3600), "hour"
  elseif diff < 86400 * 30 then
    n, unit = math.floor(diff / 86400), "day"
  elseif diff < 86400 * 365 then
    n, unit = math.floor(diff / (86400 * 30)), "month"
  else
    n, unit = math.floor(diff / (86400 * 365)), "year"
  end
  local suffix = n == 1 and "" or "s"
  return string.format("(~%d %s%s)", n, unit, suffix)
end

---Owner as "UID:GID" or "(unavailable)".
---@param uid integer?
---@param gid integer?
---@return string
local function format_owner(uid, gid)
  if uid == nil or gid == nil then
    return "(unavailable)"
  end
  return string.format("%d:%d", uid, gid)
end

---Human label for the node type.
---@param node eda.TreeNode
---@return string
local function format_type(node)
  if node.type == "link" then
    if node.link_broken then
      return "link (broken)"
    end
    return "link"
  end
  return node.type
end

---Relative path from the explorer root, falls back to absolute.
---@param path string
---@param root_path string?
---@return string
local function format_relative_path(path, root_path)
  if not root_path or root_path == "" then
    return path
  end
  if path == root_path then
    return "."
  end
  local prefix = root_path .. "/"
  if path:sub(1, #prefix) == prefix then
    return path:sub(#prefix + 1)
  end
  return path
end

---The type character for `format_mode`.
---@param node eda.TreeNode
---@return string
local function type_char_of(node)
  if node.type == "directory" then
    return "d"
  end
  if node.type == "link" then
    return "l"
  end
  return "-"
end

-- ========== scan_direct_children (single-level, authoritative) ==========

---Count direct children of a directory without recursion.
---On error returns a table with `error` set instead of counts.
---@param path string
---@return { total: integer, file: integer, directory: integer, link: integer, other: integer, error: string? }
local function scan_direct_children(path)
  local handle, err = vim.uv.fs_scandir(path)
  if not handle then
    return { error = tostring(err or "failed to read directory") }
  end
  local counts = { total = 0, file = 0, directory = 0, link = 0, other = 0 }
  while true do
    local name, t = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    counts.total = counts.total + 1
    if t == "file" or t == "directory" or t == "link" then
      counts[t] = counts[t] + 1
    else
      counts.other = counts.other + 1
    end
  end
  return counts
end

-- ========== build_lines ==========

---@class eda.InspectExtmark
---@field row integer 0-indexed
---@field col_start integer
---@field col_end integer
---@field hl string

---@class eda.InspectBuild
---@field lines string[]
---@field extmarks eda.InspectExtmark[]

---Render the inspect content as an array of plain text lines + highlight specs.
---@param node eda.TreeNode
---@param lstat table? vim.uv.fs_lstat result of node.path
---@param target_stat table? vim.uv.fs_stat result (target for symlink, or same as lstat)
---@param dir_count table? scan_direct_children result (directories only)
---@param root_path string?
---@param now integer? epoch seconds for relative-time rendering (default: os.time())
---@return eda.InspectBuild
local function build_lines(node, lstat, target_stat, dir_count, root_path, now)
  now = now or os.time()
  local lines = {}
  local extmarks = {}

  local function push(text)
    -- returns 0-indexed row for extmark API
    table.insert(lines, text)
    return #lines - 1
  end

  ---Push a key/value row with an optional muted tail.
  ---Main value uses `main_hl` (default EdaInspectValue); muted suffix, when
  ---present, is separated by 2 spaces and highlighted with EdaInspectValueMuted.
  ---@param label string
  ---@param main string
  ---@param muted string? optional decayed/parenthesized suffix
  ---@param main_hl string? override for the main value hl group
  local function push_kv(label, main, muted, main_hl)
    local padded_label = string.format("  %-14s", label)
    local text = padded_label .. main
    if muted then
      text = text .. "  " .. muted
    end
    local row = push(text)
    table.insert(extmarks, { row = row, col_start = 2, col_end = 2 + #label, hl = "EdaInspectLabel" })
    local main_start = #padded_label
    local main_end = main_start + #main
    table.insert(extmarks, { row = row, col_start = main_start, col_end = main_end, hl = main_hl or "EdaInspectValue" })
    if muted then
      table.insert(extmarks, { row = row, col_start = main_end + 2, col_end = #text, hl = "EdaInspectValueMuted" })
    end
  end

  local function timestamp(sec)
    return format_time(sec), format_relative_time(sec, now)
  end

  if not lstat then
    push_kv("Path", node.path)
    push_kv("Error", "(stat failed)", nil, "EdaInspectError")
    return { lines = lines, extmarks = extmarks }
  end

  push_kv("Path", format_relative_path(node.path, root_path))
  push_kv("Type", format_type(node))
  if node.type == "directory" then
    push_kv("Size", "-")
  else
    local size_main, size_muted = format_size(lstat.size)
    push_kv("Size", size_main, size_muted)
  end
  local perm_main, perm_muted = format_mode(lstat.mode, type_char_of(node))
  push_kv("Permissions", perm_main, perm_muted)
  push_kv("Owner", format_owner(lstat.uid, lstat.gid))

  local created_main, created_muted = timestamp(lstat.birthtime and lstat.birthtime.sec or 0)
  local modified_main, modified_muted = timestamp(lstat.mtime and lstat.mtime.sec or 0)
  local accessed_main, accessed_muted = timestamp(lstat.atime and lstat.atime.sec or 0)
  push_kv("Created", created_main, created_muted)
  push_kv("Modified", modified_main, modified_muted)
  push_kv("Accessed", accessed_main, accessed_muted)

  if node.type == "link" then
    push("")
    push_kv("Target", node.link_target or "(unknown)", nil, "EdaInspectValueMuted")
    if node.link_broken then
      push_kv("Target exists", "false (broken)", nil, "EdaInspectError")
    else
      push_kv("Target exists", "true")
      if target_stat then
        local tsize_main, tsize_muted = format_size(target_stat.size)
        push_kv("Target size", tsize_main, tsize_muted)
        push_kv("Target type", target_stat.type or "file")
      end
    end
  end

  if node.type == "directory" then
    push("")
    if dir_count then
      if dir_count.error then
        push_kv("Entries", "(" .. dir_count.error .. ")", nil, "EdaInspectError")
      else
        local main = tostring(dir_count.total)
        local muted =
          string.format("(%d files, %d dirs, %d links)", dir_count.file, dir_count.directory, dir_count.link)
        push_kv("Entries", main, muted)
      end
    else
      push_kv("Entries", "(unavailable)", nil, "EdaInspectError")
    end
  end

  return { lines = lines, extmarks = extmarks }
end

-- ========== Layout ==========

---Compute the floating window config for the inspect dialog.
---Cursor-anchored: placed below the cursor (NW/row=1) by default; flips above
---(SW/row=0) when there isn't enough vertical room below. The title row is
---intentionally omitted — path info is already rendered in the content body.
---@param build eda.InspectBuild
---@param editor { lines: integer, columns: integer, cmdheight: integer, screen_row: integer }
---@return table
local function compute_inspect_layout(build, editor)
  local max_line_width = 0
  for _, line in ipairs(build.lines) do
    max_line_width = math.max(max_line_width, vim.api.nvim_strwidth(line))
  end
  local width = math.max(40, max_line_width + 4)
  local height = math.min(#build.lines, 25)
  if height < 1 then
    height = 1
  end

  -- Reserve 1 row for the cursor line itself so the float sits directly below it.
  local available_below = editor.lines - editor.screen_row - editor.cmdheight - 1
  local row, anchor
  if available_below >= height + 1 then
    row, anchor = 1, "NW"
  else
    row, anchor = 0, "SW"
  end

  return {
    relative = "cursor",
    width = width,
    height = height,
    row = row,
    col = 0,
    anchor = anchor,
    style = "minimal",
    border = "rounded",
    zindex = 52,
    footer = " <leader>i: close ",
    footer_pos = "center",
  }
end

-- ========== Internal helpers ==========

---@param ctx table?
---@return string?
local function root_path_from_ctx(ctx)
  if not (ctx and ctx.store and ctx.store.root_id) then
    return nil
  end
  local root = ctx.store:get(ctx.store.root_id)
  return root and root.path or nil
end

---@param bufnr integer
---@param extmarks eda.InspectExtmark[]
local function apply_extmarks(bufnr, extmarks)
  vim.api.nvim_buf_clear_namespace(bufnr, _ns_hl, 0, -1)
  for _, mark in ipairs(extmarks) do
    vim.api.nvim_buf_set_extmark(bufnr, _ns_hl, mark.row, mark.col_start, {
      end_col = mark.col_end,
      hl_group = mark.hl,
    })
  end
end

-- ========== Public API ==========

---Whether the inspect float is currently visible.
---@return boolean
function M.is_visible()
  return _state ~= nil and vim.api.nvim_win_is_valid(_state.winid)
end

---Close the inspect float (no-op if not visible).
function M.close()
  if _state and util.is_valid_win(_state.winid) then
    vim.api.nvim_win_close(_state.winid, true)
  end
  _state = nil
end

---Build the content for a node: stat + extra + rendered lines/extmarks.
---@param ctx table?
---@param node eda.TreeNode
---@return eda.InspectBuild
local function build_for_node(ctx, node)
  ---@diagnostic disable-next-line: param-type-mismatch
  local lstat = vim.uv.fs_lstat(node.path)
  local target_stat = lstat
  if node.type == "link" and not node.link_broken then
    target_stat = vim.uv.fs_stat(node.path)
  end
  local dir_count = nil
  if node.type == "directory" then
    dir_count = scan_direct_children(node.path)
  end
  local root_path = root_path_from_ctx(ctx)
  return build_lines(node, lstat, target_stat, dir_count, root_path)
end

---Current editor layout context (for compute_inspect_layout).
---@return { lines: integer, columns: integer, cmdheight: integer, screen_row: integer }
local function current_editor_ctx()
  return {
    lines = vim.o.lines,
    columns = vim.o.columns,
    cmdheight = vim.o.cmdheight,
    screen_row = vim.fn.screenrow(),
  }
end

---Open an inspect float for the given node.
---@param ctx table?
---@param node eda.TreeNode
function M.show(ctx, node)
  M.close()

  local build = build_for_node(ctx, node)
  local layout = compute_inspect_layout(build, current_editor_ctx())

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, build.lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "eda_inspect"

  apply_extmarks(buf, build.extmarks)

  -- Open without entering: the inspect float is auxiliary info; focus stays in the explorer
  -- so the user can keep navigating. q / <Esc> / <leader>i keymaps below remain reachable
  -- via <C-w>w as a safety net when the user deliberately focuses the float.
  local win = vim.api.nvim_open_win(buf, false, layout)
  vim.wo[win].winhl = "FloatBorder:EdaInspectBorder,FloatFooter:EdaInspectFooter"

  _state = {
    winid = win,
    bufnr = buf,
    node_path = node.path,
  }

  local map_opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", M.close, map_opts)
  vim.keymap.set("n", "<Esc>", M.close, map_opts)
  vim.keymap.set("n", "<leader>i", M.close, map_opts)
end

---Update the currently-open inspect float for a new node. No-op if hidden;
---closes the float if `node` is nil (sticky mode lands on a line without a node).
---@param ctx table?
---@param node eda.TreeNode?
function M.update(ctx, node)
  if not M.is_visible() then
    return
  end
  if not node then
    M.close()
    return
  end
  ---@cast _state eda.InspectState
  local build = build_for_node(ctx, node)
  local layout = compute_inspect_layout(build, current_editor_ctx())

  vim.bo[_state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(_state.bufnr, 0, -1, false, build.lines)
  vim.bo[_state.bufnr].modifiable = false
  apply_extmarks(_state.bufnr, build.extmarks)

  _state.node_path = node.path

  if layout.width < 10 or layout.height < 3 then
    M.close()
    return
  end
  vim.api.nvim_win_set_config(_state.winid, layout)
end

---Toggle the inspect float for a node (close if visible, else show).
---@param ctx table?
---@param node eda.TreeNode
function M.toggle(ctx, node)
  if M.is_visible() then
    M.close()
  else
    M.show(ctx, node)
  end
end

---Recompute layout after the editor resizes. No-op if hidden.
function M.reposition()
  if not M.is_visible() then
    _state = nil
    return
  end
  ---@cast _state eda.InspectState
  local lines = vim.api.nvim_buf_get_lines(_state.bufnr, 0, -1, false)
  local build = { lines = lines, extmarks = {} }

  local layout = compute_inspect_layout(build, current_editor_ctx())

  if layout.width < 10 or layout.height < 3 then
    M.close()
    return
  end
  vim.api.nvim_win_set_config(_state.winid, layout)
end

-- ========== Test exports (prefixed `_` to signal private-but-testable) ==========

M._format_size = format_size
M._format_mode = format_mode
M._format_time = format_time
M._format_relative_time = format_relative_time
M._build_lines = build_lines
M._scan_direct_children = scan_direct_children
M._compute_inspect_layout = compute_inspect_layout

return M
