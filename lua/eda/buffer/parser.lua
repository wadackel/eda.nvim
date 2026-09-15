local util = require("eda.util")

local M = {}

---@class eda.ParsedLine
---@field indent integer Indentation level (depth)
---@field node_id integer? Existing node ID from extmark, nil for new entries
---@field name string The file/directory name
---@field is_dir boolean Whether the entry is a directory (trailing /)
---@field parent_path string?
---@field full_path string?
---@field line_nr integer?
---@field text string? Line content after the indent, as the user currently has it

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
---@param header_ns? integer Namespace whose marks tag the rows that are not entries
---  (header, divider, empty-state anchor). A row count would be wrong the moment the
---  user deletes a header row, taking the entries below it down with the offset.
---@param snapshot? eda.RenderSnapshot Last render, used to recover names that cannot be
---  spelled in the buffer (a leading space reads back as indentation, a newline cannot
---  be written at all). Without it such a line parses as a different entry.
---@return eda.ParsedLine[] parsed Lines with parent_path added
function M.parse_lines(bufnr, ns_id, indent_width, root_path, header_ns, snapshot)
  local entries = snapshot and snapshot.entries or {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local result = {}

  -- Batch fetch: all lines and all extmarks at once
  local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, line_count, false)
  local all_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, { details = true })

  local is_header_row = {}
  if header_ns then
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, header_ns, 0, -1, { details = true })) do
      if not (m[4] and m[4].invalid) then
        is_header_row[m[2]] = true
      end
    end
  end

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
    local line_nr = i - 1

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

    local node_id = mark_by_row[line_nr]
    local rendered = node_id and entries[node_id]
    local rendered_name = rendered and rendered.name
    if rendered_name and rendered.display then
      name = rendered_name
      is_dir = rendered.display:sub(-1) == "/"
    end

    if name == "" or is_header_row[line_nr] then
      goto continue
    end

    -- Pop stack until we find a parent at a lower depth
    while #stack > 1 and stack[#stack].depth >= indent do
      table.remove(stack)
    end

    local parent_path = stack[#stack].path
    local full_path = util.joinpath(parent_path, name)

    table.insert(result, {
      line_nr = line_nr,
      indent = indent,
      node_id = node_id,
      name = name,
      is_dir = is_dir,
      parent_path = parent_path,
      full_path = full_path,
      text = text,
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
