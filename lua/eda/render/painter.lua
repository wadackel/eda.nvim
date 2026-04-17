local Node = require("eda.tree.node")

-- U+F0B0 (nf-fa-filter). Built via string.char to avoid PUA-character dropping
-- by tooling that cannot safely pass private-use code points through string edits.
local FILTER_ICON = string.char(0xef, 0x82, 0xb0)
local FILTER_LABEL = " " .. FILTER_ICON .. " git changes "

-- Exported so init.lua can reuse the same glyphs in the float title and in the
-- "No git changes" empty-state message without duplicating the byte escape.
local Exports = {
  FILTER_ICON = FILTER_ICON,
  FILTER_LABEL = FILTER_LABEL,
}

---Build the virt_text array for icon extmarks, optionally prepending a prefix.
---@param entry table Decoration cache entry
---@return table[] virt_text array
local function build_icon_virt_text(entry)
  local vt = {}
  if entry.prefix_text then
    vt[#vt + 1] = { entry.prefix_text, entry.prefix_hl }
  end
  if entry.icon_text then
    vt[#vt + 1] = { entry.icon_text, entry.icon_hl }
  end
  return vt
end

---@class eda.RenderSnapshot
---@field entries table<integer, { line: integer, path: string }>

---@class eda.Painter
---@field bufnr integer
---@field ns_ids integer  Namespace for node ID extmarks
---@field ns_hl integer   Namespace for highlight extmarks (used by decoration provider)
---@field ns_icon integer  Namespace for icon extmarks (non-ephemeral; Neovim bug: ephemeral inline virt_text not rendered)
---@field ns_header integer Namespace for header extmarks
---@field indent_width integer
---@field header_lines integer Number of header lines (0, 1, or 2)
---@field snapshot eda.RenderSnapshot
---@field _decoration_cache table<integer, { prefix_text: string?, prefix_hl: string?, icon_text: string?, icon_hl: string, name_hl: string|string[], suffix: string?, suffix_hl: string, link_suffix: string?, link_suffix_hl: string? }>
---@field _flat_lines eda.FlatLine[] Current flat lines for decoration provider
---@field _line_lengths integer[] Pre-computed line text lengths for decoration provider
---@field _row_to_fl table<integer, integer> Buffer row -> flat_lines index mapping
---@field _replaying boolean?
---@field paint fun(self: eda.Painter, flat_lines: eda.FlatLine[], decorations?: eda.Decoration[], opts?: table)
---@field paint_incremental fun(self: eda.Painter, flat_lines: eda.FlatLine[], decorations?: eda.Decoration[], opts?: table, hint: { toggled_node_id: integer }): boolean
---@field get_snapshot fun(self: eda.Painter): eda.RenderSnapshot
---@field resync_highlights fun(self: eda.Painter)

local Painter = {}
Painter.__index = Painter

---Create a new painter for a buffer.
---@param bufnr integer
---@param indent_width? integer
---@return eda.Painter
function Painter.new(bufnr, indent_width)
  local self = setmetatable({
    bufnr = bufnr,
    ns_ids = vim.api.nvim_create_namespace("eda_node_ids"),
    -- Each Painter needs its own namespace because nvim_set_decoration_provider
    -- registers a single global callback per namespace. Sharing would overwrite.
    ns_hl = vim.api.nvim_create_namespace(""),
    -- Separate namespace for icon extmarks: Neovim has a known bug where
    -- ephemeral extmarks with virt_text_pos="inline" are not rendered
    -- (neovim/neovim#24797). Icons must use non-ephemeral extmarks.
    ns_icon = vim.api.nvim_create_namespace(""),
    ns_header = vim.api.nvim_create_namespace("eda_header"),
    indent_width = indent_width or 2,
    header_lines = 0,
    snapshot = { entries = {} },
    _decoration_cache = {},
    _flat_lines = {},
    _line_lengths = {},
    _row_to_fl = {},
  }, Painter)

  -- Register decoration provider for ephemeral highlights
  vim.api.nvim_set_decoration_provider(self.ns_hl, {
    on_win = function(_, _, buf, _, _)
      if buf ~= self.bufnr then
        return false
      end
      self:_resync_on_redraw()
    end,
    on_line = function(_, _, buf, row)
      if buf ~= self.bufnr then
        return
      end
      local fl_index = self._row_to_fl[row]
      if not fl_index then
        return
      end
      local fl = self._flat_lines[fl_index]
      if not fl then
        return
      end
      local entry = self._decoration_cache[fl.node_id]
      if not entry then
        return
      end
      local indent_len = fl.depth * self.indent_width
      local line_len = self._line_lengths[fl_index] or 0

      -- Note: Icon extmarks are set in paint() as non-ephemeral because
      -- Neovim does not render ephemeral inline virtual text (neovim/neovim#24797).

      -- Name highlight.
      -- Neovim does not resolve link chains inside hl_group arrays, so link-only
      -- groups (e.g. EdaMarkedName, EdaGitIgnoredName) lose their attributes if
      -- passed as an array. Emit one single-string extmark per element with
      -- stair-stepped priority so each element resolves its own link chain; the
      -- later element wins overlapping attrs.
      if indent_len < line_len then
        local name_hl = entry.name_hl
        if type(name_hl) == "string" then
          vim.api.nvim_buf_set_extmark(buf, self.ns_hl, row, indent_len, {
            end_col = line_len,
            hl_group = name_hl,
            ephemeral = true,
          })
        else
          for i, hl in ipairs(name_hl) do
            vim.api.nvim_buf_set_extmark(buf, self.ns_hl, row, indent_len, {
              end_col = line_len,
              hl_group = hl,
              priority = 200 + i,
              ephemeral = true,
            })
          end
        end
      end

      -- Link suffix (symlink target path, rendered first at EOL)
      if entry.link_suffix then
        vim.api.nvim_buf_set_extmark(buf, self.ns_hl, row, 0, {
          virt_text = { { entry.link_suffix, entry.link_suffix_hl } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = true,
        })
      end

      -- Suffix (git status, rendered after link suffix)
      if entry.suffix then
        vim.api.nvim_buf_set_extmark(buf, self.ns_hl, row, 0, {
          virt_text = { { entry.suffix, entry.suffix_hl } },
          virt_text_pos = "eol",
          hl_mode = "combine",
          ephemeral = true,
        })
      end
    end,
  })

  return self
end

---Build header text from root_path and format setting.
---@param root_path string
---@param format string|fun(root_path: string): string
---@return string
function Painter._build_header_text(root_path, format)
  if type(format) == "function" then
    return format(root_path)
  end

  if format == "full" then
    return root_path
  end

  if format == "minimal" then
    local path = vim.fn.fnamemodify(root_path, ":~")
    -- Shorten intermediate directories to first character
    local parts = vim.split(path, "/", { plain = true })
    if #parts > 1 then
      for i = 1, #parts - 1 do
        if parts[i] ~= "" and parts[i] ~= "~" then
          -- Use first character (handle multi-byte)
          parts[i] = vim.fn.strcharpart(parts[i], 0, 1)
        end
      end
    end
    return table.concat(parts, "/")
  end

  -- "short" (default)
  return vim.fn.fnamemodify(root_path, ":~")
end

---Build the display text for a single flat line.
---@param flat_line eda.FlatLine
---@return string
function Painter:_build_line(flat_line)
  local indent = string.rep(" ", flat_line.depth * self.indent_width)
  local node = flat_line.node
  local name = node.name
  if Node.is_dir(node) then
    name = name .. "/"
  end
  return indent .. name
end

---Check whether a highlight group has any visual attributes.
---nvim_get_hl returns { default = true } for groups set with only `default = true`,
---so next(resolved) ~= nil is insufficient.
---@param name string
---@return boolean
local function has_visual_attrs(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return hl.fg ~= nil
    or hl.bg ~= nil
    or hl.sp ~= nil
    or hl.bold == true
    or hl.italic == true
    or hl.underline == true
    or hl.strikethrough == true
    or hl.reverse == true
end

---Compute the resolved name highlight for a node.
---When the decoration provides a name_hl that resolves to an empty highlight group
---(no visual attributes), the default name highlight is used instead. This allows
---EdaGit*Name groups to be transparent by default while still supporting user
---customization via colorschemes or nvim_set_hl.
---When multiple decorators contribute name_hl (e.g., git + cut), the result is a
---string[] for Neovim 0.11's hl_group array support. Only groups with visual
---attributes are included; base_hl is used as a fallback when none qualify.
---@param node eda.TreeNode
---@param dec eda.Decoration?
---@return string|string[]
local function resolve_name_hl(node, dec)
  local base_hl = "EdaFileName"
  if Node.is_dir(node) then
    base_hl = node.open and "EdaOpenedDirectoryName" or "EdaDirectoryName"
  elseif node.error then
    base_hl = "EdaErrorNode"
  elseif node.link_broken then
    base_hl = "EdaBrokenSymlink"
  elseif Node.is_link(node) then
    base_hl = "EdaSymlink"
  end
  -- Determine symlink highlight to compose (nil for non-symlink nodes).
  -- Uses node.link_target (not Node.is_link) because follow_symlinks=true
  -- converts directory symlinks to type="directory" while retaining link_target.
  local symlink_hl = nil
  if node.link_broken then
    symlink_hl = "EdaBrokenSymlink"
  elseif node.link_target then
    symlink_hl = "EdaSymlink"
  end

  -- Helper: append symlink_hl to a result (bypasses has_visual_attrs gating)
  local function with_symlink(result)
    if not symlink_hl then
      return result
    end
    if type(result) == "string" then
      if result == symlink_hl then
        return result
      end
      return { result, symlink_hl }
    end
    -- Array: append if not already present
    for _, hl in ipairs(result) do
      if hl == symlink_hl then
        return result
      end
    end
    result[#result + 1] = symlink_hl
    return result
  end

  if not dec or not dec.name_hl then
    return with_symlink(base_hl)
  end
  -- Single string path (most common)
  if type(dec.name_hl) == "string" then
    local name_hl_str = dec.name_hl --[[@as string]]
    if has_visual_attrs(name_hl_str) then
      return with_symlink(name_hl_str)
    end
    return with_symlink(base_hl)
  end
  -- Array path: filter to groups with visual attributes
  local visual = {}
  local name_hl_arr = dec.name_hl --[[@as string[] ]]
  for _, hl in ipairs(name_hl_arr) do
    if has_visual_attrs(hl) then
      visual[#visual + 1] = hl
    end
  end
  if #visual == 0 then
    return with_symlink(base_hl)
  end
  if #visual == 1 then
    return with_symlink(visual[1])
  end
  return with_symlink(visual)
end

---Build a cache entry for a decoration.
---@param dec eda.Decoration?
---@param node eda.TreeNode
---@param name_hl string|string[]
---@param separator string
---@return { prefix_text: string?, prefix_hl: string?, icon_text: string?, icon_hl: string, name_hl: string|string[], suffix: string?, suffix_hl: string, link_suffix: string?, link_suffix_hl: string? }?
local function build_cache_entry(dec, node, name_hl, separator)
  if not dec then
    return nil
  end
  return {
    prefix_text = dec.prefix and dec.prefix ~= "" and (dec.prefix .. " ") or nil,
    prefix_hl = dec.prefix_hl,
    icon_text = dec.icon and dec.icon ~= "" and (dec.icon .. separator) or nil,
    icon_hl = dec.icon_hl or (Node.is_dir(node) and "EdaDirectoryIcon") or "EdaFileIcon",
    name_hl = name_hl,
    suffix = dec.suffix,
    suffix_hl = dec.suffix_hl or "Comment",
    link_suffix = dec.link_suffix,
    link_suffix_hl = dec.link_suffix_hl or "Comment",
  }
end

---Paint the full buffer from flat lines.
---Decorations are applied ephemerally by the decoration provider on each redraw.
---@param flat_lines eda.FlatLine[]
---@param decorations? eda.Decoration[]
---@param opts? { root_path?: string, header?: eda.HeaderConfig|false, kind?: string, icon?: eda.IconConfig, filter_active?: boolean, empty_message?: string }
function Painter:paint(flat_lines, decorations, opts)
  opts = opts or {}
  local separator = opts.icon and opts.icon.separator or " "
  local lines = {}
  local new_snapshot = { entries = {} }

  -- Determine header lines
  local header_text = nil
  local show_header = false
  if opts.root_path and opts.header and opts.header ~= false and opts.kind ~= "float" then
    local format = opts.header.format
    if format and format ~= false then
      header_text = Painter._build_header_text(opts.root_path, format)
      show_header = true
    end
  end

  local show_divider = show_header and opts.header.divider
  self.header_lines = show_header and (show_divider and 2 or 1) or 0
  local offset = self.header_lines

  if show_header then
    lines[1] = header_text
    if show_divider then
      local winid = vim.fn.bufwinid(self.bufnr)
      local win_width = winid > 0 and vim.api.nvim_win_get_width(winid) or vim.o.columns
      local sep_char = string.char(0xe2, 0x94, 0x80) -- UTF-8 for "─"
      lines[2] = string.rep(sep_char, win_width)
    end
  end

  for i, fl in ipairs(flat_lines) do
    lines[offset + i] = self:_build_line(fl)
    new_snapshot.entries[fl.node_id] = { line = offset + i - 1, path = fl.node.path }
  end

  -- Empty-state message: render after the header/divider shell when the tree has
  -- no flat lines. Consumers pass this when the filter is active and no files
  -- match, or during git-status loading via the caller's own branch.
  local empty_row = nil
  if opts.empty_message and #flat_lines == 0 then
    empty_row = offset + 1
    lines[empty_row] = opts.empty_message
  end

  -- Set buffer text
  vim.bo[self.bufnr].modifiable = true
  local saved_undolevels = vim.bo[self.bufnr].undolevels
  vim.bo[self.bufnr].undolevels = -1
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  vim.bo[self.bufnr].undolevels = saved_undolevels

  -- Header extmarks (non-ephemeral, only on structure change)
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_header, 0, -1)
  if show_header then
    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_header, 0, 0, {
      end_col = #lines[1],
      hl_group = "EdaRootName",
    })
    if opts.filter_active then
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_header, 0, 0, {
        virt_text = { { FILTER_LABEL, "EdaFilterIndicator" } },
        virt_text_pos = "right_align",
      })
    end
    if show_divider then
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_header, 1, 0, {
        end_col = #lines[2],
        hl_group = "EdaDivider",
      })
    end
  end
  if empty_row then
    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_header, empty_row - 1, 0, {
      end_col = #lines[empty_row],
      hl_group = "EdaLoadingNode",
    })
  end

  -- Node ID extmarks (non-ephemeral, needed for edit/parse)
  -- Always clear and re-place: nvim_buf_set_lines can invalidate extmarks
  -- even when the node_id sequence is unchanged, causing the parser to return
  -- nil node_ids and diff.lua to treat those lines as DELETE (#154).
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_ids, 0, -1)
  for i, fl in ipairs(flat_lines) do
    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_ids, offset + i - 1, 0, {
      id = fl.node_id,
      undo_restore = true,
      invalidate = true,
    })
  end

  -- Build row -> flat_lines index mapping
  self._row_to_fl = {}
  for i = 1, #flat_lines do
    self._row_to_fl[offset + i - 1] = i
  end

  -- Build decoration cache (Lua tables only, no API calls)
  -- The decoration provider will read this cache on each redraw
  self._decoration_cache = {}
  for i, fl in ipairs(flat_lines) do
    local dec = decorations and decorations[i] or nil
    local name_hl = resolve_name_hl(fl.node, dec)
    self._decoration_cache[fl.node_id] = build_cache_entry(dec, fl.node, name_hl, separator)
  end

  -- Icon extmarks (non-ephemeral): Neovim has a known bug where ephemeral
  -- extmarks with virt_text_pos="inline" are not rendered (neovim/neovim#24797).
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, 0, -1)
  for i, fl in ipairs(flat_lines) do
    local entry = self._decoration_cache[fl.node_id]
    if entry and (entry.icon_text or entry.prefix_text) then
      local indent_len = fl.depth * self.indent_width
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_icon, offset + i - 1, indent_len, {
        virt_text = build_icon_virt_text(entry),
        virt_text_pos = "inline",
        right_gravity = false,
      })
    end
  end

  -- Store flat_lines and line lengths for decoration provider
  self._flat_lines = flat_lines
  self._line_lengths = {}
  for i = 1, #flat_lines do
    self._line_lengths[i] = #lines[offset + i]
  end

  vim.bo[self.bufnr].modified = false
  self.snapshot = new_snapshot
end

---Incrementally update the buffer for a single directory toggle (collapse/expand).
---Falls back by returning false when the change is not a single contiguous block.
---@param flat_lines eda.FlatLine[]
---@param decorations? eda.Decoration[]
---@param opts? { root_path?: string, header?: eda.HeaderConfig|false, kind?: string, icon?: eda.IconConfig }
---@param hint { toggled_node_id: integer }
---@return boolean success
function Painter:paint_incremental(flat_lines, decorations, opts, hint)
  if #self._flat_lines == 0 then
    return false
  end

  local toggled_id = hint.toggled_node_id
  local offset = self.header_lines

  -- Build lookup tables
  local old_idx_by_id = {}
  for i, fl in ipairs(self._flat_lines) do
    old_idx_by_id[fl.node_id] = i
  end
  local new_idx_by_id = {}
  for i, fl in ipairs(flat_lines) do
    new_idx_by_id[fl.node_id] = i
  end

  -- Guard: toggled node must exist in both old and new
  if not old_idx_by_id[toggled_id] or not new_idx_by_id[toggled_id] then
    return false
  end

  local old_len = #self._flat_lines
  local new_len = #flat_lines
  local is_collapse = old_len > new_len
  local is_expand = new_len > old_len

  if not is_collapse and not is_expand then
    return false
  end

  -- Determine the contiguous range of inserted/deleted lines
  local del_start, del_count -- 1-based index in old flat_lines, for collapse
  local ins_start, ins_count -- 1-based index in new flat_lines, for expand

  if is_collapse then
    local toggled_old_i = old_idx_by_id[toggled_id]
    -- Find contiguous descendants after the toggled node in old that are absent in new
    del_start = toggled_old_i + 1
    del_count = 0
    for j = del_start, old_len do
      if new_idx_by_id[self._flat_lines[j].node_id] then
        break
      end
      del_count = del_count + 1
    end
    if del_count == 0 or del_count ~= old_len - new_len then
      return false
    end
  else -- expand
    local toggled_new_i = new_idx_by_id[toggled_id]
    -- Find contiguous descendants after the toggled node in new that are absent in old
    ins_start = toggled_new_i + 1
    ins_count = 0
    for j = ins_start, new_len do
      if old_idx_by_id[flat_lines[j].node_id] then
        break
      end
      ins_count = ins_count + 1
    end
    if ins_count == 0 or ins_count ~= new_len - old_len then
      return false
    end
  end

  -- Validate: surviving node_ids must match between old and new
  if is_collapse then
    for i, fl in ipairs(flat_lines) do
      local old_i = old_idx_by_id[fl.node_id]
      if not old_i then
        return false
      end
      -- Check order is preserved (accounting for the gap)
      local expected_old_i = i <= old_idx_by_id[toggled_id] and i or (i + del_count)
      if old_i ~= expected_old_i then
        return false
      end
    end
  else
    for i, fl in ipairs(self._flat_lines) do
      local new_i = new_idx_by_id[fl.node_id]
      if not new_i then
        return false
      end
      local toggled_new_i = new_idx_by_id[toggled_id]
      local expected_new_i = i <= toggled_new_i and i or (i + ins_count)
      if new_i ~= expected_new_i then
        return false
      end
    end
  end

  -- === All validation passed — now mutate ===

  local separator = opts and opts.icon and opts.icon.separator or " "

  vim.bo[self.bufnr].modifiable = true
  local saved_undolevels = vim.bo[self.bufnr].undolevels
  vim.bo[self.bufnr].undolevels = -1

  if is_collapse then
    local start_row = offset + del_start - 1
    local end_row = start_row + del_count
    -- Clear ns_ids and ns_icon extmarks BEFORE deleting lines (shift-safe).
    -- nvim_buf_set_lines does not remove point extmarks; they collapse onto
    -- the first surviving row, leaving stale icons.
    vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_ids, start_row, end_row)
    vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, start_row, end_row)
    -- Delete lines
    vim.api.nvim_buf_set_lines(self.bufnr, start_row, end_row, false, {})
    -- Remove decoration cache entries for deleted nodes
    for j = del_start, del_start + del_count - 1 do
      self._decoration_cache[self._flat_lines[j].node_id] = nil
    end
  else -- expand
    local insert_row = offset + ins_start - 1
    -- Build new line strings
    local new_line_strings = {}
    for j = ins_start, ins_start + ins_count - 1 do
      new_line_strings[#new_line_strings + 1] = self:_build_line(flat_lines[j])
    end
    -- Clear and rebuild all ns_icon extmarks: existing icons use
    -- right_gravity=false and do not shift when lines are inserted above,
    -- leaving siblings rendered on the wrong row.
    vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, 0, -1)
    -- Insert lines
    vim.api.nvim_buf_set_lines(self.bufnr, insert_row, insert_row, false, new_line_strings)
    -- Place ns_ids extmarks for inserted nodes
    for j = 0, ins_count - 1 do
      local fl = flat_lines[ins_start + j]
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_ids, insert_row + j, 0, {
        id = fl.node_id,
        undo_restore = true,
        invalidate = true,
      })
    end
    -- Add decoration cache entries for inserted nodes
    for j = ins_start, ins_start + ins_count - 1 do
      local fl = flat_lines[j]
      local dec = decorations and decorations[j] or nil
      local name_hl = resolve_name_hl(fl.node, dec)
      self._decoration_cache[fl.node_id] = build_cache_entry(dec, fl.node, name_hl, separator)
    end
  end

  vim.bo[self.bufnr].undolevels = saved_undolevels

  -- Update toggled node's decoration cache (name_hl and icon change on toggle)
  local toggled_new_i = new_idx_by_id[toggled_id]
  local toggled_fl = flat_lines[toggled_new_i]
  local toggled_dec = decorations and decorations[toggled_new_i] or nil
  local toggled_name_hl = resolve_name_hl(toggled_fl.node, toggled_dec)
  self._decoration_cache[toggled_id] = build_cache_entry(toggled_dec, toggled_fl.node, toggled_name_hl, separator)

  -- Rebuild all icon extmarks from decoration cache.
  -- Both collapse and expand paths clear ns_icon in affected ranges, but
  -- right_gravity=false icons do not auto-shift with line edits. A full
  -- rebuild is the simplest correct approach and avoids stale icons in
  -- headless/no-redraw contexts.
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, 0, -1)
  for i, fl in ipairs(flat_lines) do
    local entry = self._decoration_cache[fl.node_id]
    if entry and (entry.icon_text or entry.prefix_text) then
      local indent_len = fl.depth * self.indent_width
      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_icon, offset + i - 1, indent_len, {
        virt_text = build_icon_virt_text(entry),
        virt_text_pos = "inline",
        right_gravity = false,
      })
    end
  end

  -- Update internal state
  self._flat_lines = flat_lines

  self._row_to_fl = {}
  for i = 1, #flat_lines do
    self._row_to_fl[offset + i - 1] = i
  end

  self._line_lengths = {}
  local buf_lines = vim.api.nvim_buf_get_lines(self.bufnr, offset, offset + #flat_lines, false)
  for i = 1, #flat_lines do
    self._line_lengths[i] = buf_lines[i] and #buf_lines[i] or 0
  end

  local new_snapshot = { entries = {} }
  for i, fl in ipairs(flat_lines) do
    new_snapshot.entries[fl.node_id] = { line = offset + i - 1, path = fl.node.path }
  end
  self.snapshot = new_snapshot

  vim.bo[self.bufnr].modified = false
  return true
end

---Resync _row_to_fl and icon extmarks from current ns_ids extmark positions.
---Called by on_win on each redraw to keep decorations aligned after buffer edits.
---ns_ids extmarks (right_gravity=true) are the source of truth for row positions.
function Painter:_resync_on_redraw()
  local marks = vim.api.nvim_buf_get_extmarks(self.bufnr, self.ns_ids, 0, -1, { details = true })
  local idx_by_node_id = {}
  for i, fl in ipairs(self._flat_lines) do
    idx_by_node_id[fl.node_id] = i
  end

  -- Rebuild _row_to_fl (lightweight: Lua table only)
  local new_map = {}
  for _, m in ipairs(marks) do
    if not (m[4] and m[4].invalid) then
      local idx = idx_by_node_id[m[1]]
      if idx then
        new_map[m[2]] = idx
      end
    end
  end
  self._row_to_fl = new_map

  -- Check if icon extmarks need repositioning by comparing with ns_ids positions
  local icon_marks = vim.api.nvim_buf_get_extmarks(self.bufnr, self.ns_icon, 0, -1, {})
  local icons_need_resync = #marks ~= #icon_marks
  if not icons_need_resync then
    local icon_idx = 1
    for _, m in ipairs(marks) do
      if not (m[4] and m[4].invalid) then
        local fl_idx = idx_by_node_id[m[1]]
        if fl_idx then
          local entry = self._decoration_cache[self._flat_lines[fl_idx].node_id]
          if entry and (entry.icon_text or entry.prefix_text) then
            if icon_idx > #icon_marks or icon_marks[icon_idx][2] ~= m[2] then
              icons_need_resync = true
              break
            end
            icon_idx = icon_idx + 1
          end
        end
      end
    end
  end

  if icons_need_resync then
    vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, 0, -1)
    for _, m in ipairs(marks) do
      if not (m[4] and m[4].invalid) then
        local fl_idx = idx_by_node_id[m[1]]
        if fl_idx then
          local fl = self._flat_lines[fl_idx]
          local entry = self._decoration_cache[fl.node_id]
          if entry and (entry.icon_text or entry.prefix_text) then
            local indent_len = fl.depth * self.indent_width
            vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_icon, m[2], indent_len, {
              virt_text = build_icon_virt_text(entry),
              virt_text_pos = "inline",
              right_gravity = false,
            })
          end
        end
      end
    end
  end
end

---Resync icon extmarks and internal caches after user edits (e.g. dd).
---Does NOT modify buffer text — only fixes extmarks and caches.
function Painter:resync_highlights()
  -- 1. Build local node_id -> FlatLine lookup from current _flat_lines
  local fl_by_id = {}
  for _, fl in ipairs(self._flat_lines) do
    fl_by_id[fl.node_id] = fl
  end

  -- 2. Get current valid extmarks from ns_ids
  local marks = vim.api.nvim_buf_get_extmarks(self.bufnr, self.ns_ids, 0, -1, { details = true })

  -- 3. Filter out invalidated extmarks and sort by row
  local valid = {}
  for _, m in ipairs(marks) do
    if not (m[4] and m[4].invalid) then
      table.insert(valid, { node_id = m[1], row = m[2] })
    end
  end
  table.sort(valid, function(a, b)
    return a.row < b.row
  end)

  -- 4. Rebuild _flat_lines from surviving extmarks
  local new_flat_lines = {}
  for _, v in ipairs(valid) do
    local fl = fl_by_id[v.node_id]
    if fl then
      table.insert(new_flat_lines, fl)
    end
  end
  self._flat_lines = new_flat_lines

  -- 5. Clear and re-place icon extmarks using actual extmark rows
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.ns_icon, 0, -1)
  local row_to_fl = {}
  for i, v in ipairs(valid) do
    local fl = fl_by_id[v.node_id]
    if fl then
      row_to_fl[v.row] = i
      local entry = self._decoration_cache[fl.node_id]
      if entry and (entry.icon_text or entry.prefix_text) then
        local indent_len = fl.depth * self.indent_width
        vim.api.nvim_buf_set_extmark(self.bufnr, self.ns_icon, v.row, indent_len, {
          virt_text = build_icon_virt_text(entry),
          virt_text_pos = "inline",
          right_gravity = false,
        })
      end
    end
  end
  self._row_to_fl = row_to_fl

  -- 6. Rebuild _line_lengths from actual extmark rows
  self._line_lengths = {}
  if #valid > 0 then
    local min_row = valid[1].row
    local max_row = valid[#valid].row
    local all_lines = vim.api.nvim_buf_get_lines(self.bufnr, min_row, max_row + 1, false)
    for i, v in ipairs(valid) do
      local fl = fl_by_id[v.node_id]
      if fl then
        local line = all_lines[v.row - min_row + 1]
        self._line_lengths[i] = line and #line or 0
      end
    end
  end
end

---Get the current render snapshot.
---@return eda.RenderSnapshot
function Painter:get_snapshot()
  return self.snapshot
end

Painter.FILTER_ICON = Exports.FILTER_ICON
Painter.FILTER_LABEL = Exports.FILTER_LABEL

return Painter
