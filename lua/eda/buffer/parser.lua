local M = {}

---@class eda.ParsedLine
---@field indent integer Indentation level (depth)
---@field node_id integer? Existing node ID from extmark, nil for new entries
---@field name string The file/directory name
---@field is_dir boolean Whether the entry is a directory (trailing /)
---@field parent_path string?
---@field full_path string?

---Parse a single buffer line.
---@param bufnr integer
---@param ns_id integer Namespace for node ID extmarks
---@param line_nr integer 0-based line number
---@param indent_width integer
---@return eda.ParsedLine
function M.parse_line(bufnr, ns_id, line_nr, indent_width)
  local line = vim.api.nvim_buf_get_lines(bufnr, line_nr, line_nr + 1, false)[1] or ""

  -- Get node_id from extmark (skip invalidated marks displaced by dd/visual d)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, { line_nr, 0 }, { line_nr, -1 }, { details = true })
  local node_id = nil
  for _, m in ipairs(marks) do
    if not (m[4] and m[4].invalid) then
      node_id = m[1]
      break
    end
  end

  -- Calculate indent level
  local leading_spaces = line:match("^(%s*)") or ""
  local indent = math.floor(#leading_spaces / indent_width)

  -- Extract name (strip leading whitespace)
  -- Icons are rendered as virtual text (not in buffer text)
  local text = line:sub(#leading_spaces + 1)
  local name = text

  -- Check if directory (trailing /)
  local is_dir = name:sub(-1) == "/"
  if is_dir then
    name = name:sub(1, -2)
  end

  return {
    indent = indent,
    node_id = node_id,
    name = name,
    is_dir = is_dir,
  }
end

---Parse all buffer lines and reconstruct parent-child relationships.
---Batches API calls for performance: 2 calls total instead of 2 per line.
---@param bufnr integer
---@param ns_id integer Namespace for node ID extmarks
---@param indent_width integer
---@param root_path string Root directory path
---@param header_lines? integer Number of header lines to skip (default 0)
---@return eda.ParsedLine[] parsed Lines with parent_path added
function M.parse_lines(bufnr, ns_id, indent_width, root_path, header_lines)
  header_lines = header_lines or 0
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local result = {}

  -- Batch fetch: all lines and all extmarks at once (2 API calls total)
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, header_lines, line_count, false)
  local all_marks = vim.api.nvim_buf_get_extmarks(
    bufnr,
    ns_id,
    { header_lines, 0 },
    { line_count - 1, -1 },
    { details = true }
  )

  -- Build row -> node_id lookup from extmarks (first valid mark per row wins)
  local mark_by_row = {}
  for _, m in ipairs(all_marks) do
    local row = m[2]
    if not mark_by_row[row] and not (m[4] and m[4].invalid) then
      mark_by_row[row] = m[1]
    end
  end

  -- Stack of { depth, path } for parent tracking
  local stack = { { depth = -1, path = root_path } }

  for i, line in ipairs(all_lines) do
    local line_nr = header_lines + i - 1

    -- Calculate indent level
    local leading_spaces = line:match("^(%s*)") or ""
    local indent = math.floor(#leading_spaces / indent_width)

    -- Extract name (strip leading whitespace)
    local text = line:sub(#leading_spaces + 1)
    local name = text

    -- Check if directory (trailing /)
    local is_dir = name:sub(-1) == "/"
    if is_dir then
      name = name:sub(1, -2)
    end

    if name == "" then
      goto continue
    end

    -- Pop stack until we find a parent at a lower depth
    while #stack > 1 and stack[#stack].depth >= indent do
      table.remove(stack)
    end

    local parent_path = stack[#stack].path
    local full_path = parent_path .. "/" .. name

    table.insert(result, {
      indent = indent,
      node_id = mark_by_row[line_nr],
      name = name,
      is_dir = is_dir,
      parent_path = parent_path,
      full_path = full_path,
    })

    -- If this is a directory, push it onto the stack
    if is_dir then
      table.insert(stack, { depth = indent, path = full_path })
    end

    ::continue::
  end

  return result
end

return M
