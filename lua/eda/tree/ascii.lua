local Node = require("eda.tree.node")
local Store = require("eda.tree.store")

local M = {}

---@param path string
---@param root_path string Explorer root (no trailing slash, except for "/")
---@return string
local function relative(path, root_path)
  return path:sub(#root_path + 2)
end

---Split a path into its segments. Empty input yields an empty array.
---@param rel string
---@return string[]
local function split_segments(rel)
  local segments = {}
  for seg in rel:gmatch("[^/]+") do
    segments[#segments + 1] = seg
  end
  return segments
end

---Sort comparator matching `Store:children` (directories first, then natural sort).
---@param a { name: string, is_dir: boolean }
---@param b { name: string, is_dir: boolean }
---@return boolean
local function compare_entries(a, b)
  if a.is_dir ~= b.is_dir then
    return a.is_dir
  end
  return Store.natural_sort_key(a.name) < Store.natural_sort_key(b.name)
end

---Render the tree rooted at `tree_node`'s ordered children into `out`.
---@param children { name: string, is_dir: boolean, children: table[]? }[]
---@param prefix string Pre-computed indent prefix for this depth
---@param out string[]
local function render_children(children, prefix, out)
  local sorted = {}
  for _, child in ipairs(children) do
    sorted[#sorted + 1] = child
  end
  table.sort(sorted, compare_entries)

  for idx, child in ipairs(sorted) do
    local is_last = idx == #sorted
    local connector = is_last and "└── " or "├── "
    local name = child.is_dir and (child.name .. "/") or child.name
    out[#out + 1] = prefix .. connector .. name
    if child.children and #child.children > 0 then
      local next_prefix = prefix .. (is_last and "    " or "│   ")
      render_children(child.children, next_prefix, out)
    end
  end
end

---Render selected nodes as an ASCII tree string suitable for pasting into
---GitHub-flavored Markdown code blocks.
---
--- - Empty input returns "".
--- - Single node short-circuits to `<relative path>` (directories suffixed with "/").
--- - Multiple nodes are rendered as a tree rooted at their common ancestor.
---   Header is "./" when the common ancestor is the explorer root.
--- - Scaffold and explicitly-selected directories render identically (both with "/").
--- - Children at each level are ordered directories-first, then natural sort,
---   matching `Store:children` (the visible order in the explorer).
---@param nodes eda.TreeNode[]
---@param root_path string Explorer root path (no trailing slash, except "/")
---@return string ASCII tree without a trailing newline
function M.render(nodes, root_path)
  if #nodes == 0 then
    return ""
  end

  if #nodes == 1 then
    local rel = relative(nodes[1].path, root_path)
    if Node.is_dir(nodes[1]) then
      return rel .. "/"
    end
    return rel
  end

  -- Build per-node segments + dir flag.
  local entries = {}
  for _, n in ipairs(nodes) do
    entries[#entries + 1] = {
      segments = split_segments(relative(n.path, root_path)),
      is_dir = Node.is_dir(n),
    }
  end

  -- Longest common segment prefix across all entries.
  local common_len = #entries[1].segments
  for i = 2, #entries do
    local other = entries[i].segments
    local max_match = math.min(common_len, #other)
    local match = 0
    for j = 1, max_match do
      if entries[1].segments[j] == other[j] then
        match = j
      else
        break
      end
    end
    common_len = match
    if common_len == 0 then
      break
    end
  end

  -- Header line: "./" if common prefix is empty, else "<common>/".
  local header
  if common_len == 0 then
    header = "./"
  else
    local parts = {}
    for j = 1, common_len do
      parts[#parts + 1] = entries[1].segments[j]
    end
    header = table.concat(parts, "/") .. "/"
  end

  -- Insert each entry (with the common prefix stripped) into a tree.
  -- Intermediate nodes are scaffold directories; the terminal segment carries
  -- the explicit is_dir flag. Re-inserting the same path is idempotent: dir-ness
  -- only ever upgrades (a parent of any selected node IS a directory).
  local root = { children = {}, index = {} }

  local function insert(entry)
    local node = root
    for j = common_len + 1, #entry.segments do
      local seg = entry.segments[j]
      local child = node.index[seg]
      if not child then
        local is_terminal = j == #entry.segments
        local seg_is_dir
        if is_terminal then
          seg_is_dir = entry.is_dir
        else
          seg_is_dir = true
        end
        child = {
          name = seg,
          is_dir = seg_is_dir,
          children = {},
          index = {},
        }
        node.index[seg] = child
        node.children[#node.children + 1] = child
      end
      node = child
    end
  end

  for _, entry in ipairs(entries) do
    -- Entries with no remaining segments after stripping the common prefix
    -- (i.e. the entry's full path == common prefix) collapse into the header.
    if #entry.segments > common_len then
      insert(entry)
    end
  end

  local out = { header }
  render_children(root.children, "", out)
  return table.concat(out, "\n")
end

return M
