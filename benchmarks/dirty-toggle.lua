vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to a 100 x 100 file fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT to the output JSON path")
local api = vim.api
local counts, active = {}, false
local preserve = require("eda.buffer.edit_preserve")
local capture = preserve.capture
preserve.capture = function(...)
  local start = vim.uv.hrtime()
  local result = capture(...)
  if active then
    counts.capture_calls = counts.capture_calls + 1
    counts.capture_ms = counts.capture_ms + (vim.uv.hrtime() - start) / 1e6
  end
  return result
end
local Parser = require("eda.buffer.parser")
local parse = Parser.parse_lines
Parser.parse_lines = function(...)
  local start = vim.uv.hrtime()
  local result = parse(...)
  if active then
    counts.parse_ms = counts.parse_ms + (vim.uv.hrtime() - start) / 1e6
  end
  return result
end
local function run()
  if #api.nvim_list_uis() == 0 then
    vim.o.lines = 40
    vim.o.columns = 140
  end
  local eda = require("eda")
  eda.setup({
    git = { enabled = false },
    header = false,
    confirm = false,
    window = { kind = "replace" },
    icon = { provider = "none" },
  })
  eda.open({ dir = fixture })
  assert(
    vim.wait(10000, function()
      return eda.get_current() and eda.get_current()._initial_scan_complete
    end, 1),
    "initial scan timeout"
  )
  local ex = eda.get_current()
  local ctx = {
    explorer = ex,
    store = ex.store,
    scanner = ex.scanner,
    buffer = ex.buffer,
    window = ex.window,
    config = require("eda.config").get(),
  }
  local action = require("eda.action")
  action.dispatch("expand_all", ctx)
  assert(
    vim.wait(10000, function()
      return #ex.buffer.flat_lines == 10100
    end, 1),
    "expand timeout"
  )
  local target = ex.buffer.flat_lines[1].node
  assert(target.type == "directory" and #target.children_ids == 100, "Expected 100 files in the first directory")
  local buf, painter = ex.buffer.bufnr, ex.buffer.painter
  local row = 103
  local rename_id = api.nvim_buf_get_extmarks(buf, painter.ns_ids, { row, 0 }, { row, -1 }, {})[1][1]
  local text = api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  api.nvim_buf_set_text(buf, row, 2, row, #text, { "renamed-benchmark.txt" })
  assert(
    api.nvim_buf_get_extmark_by_id(buf, painter.ns_ids, rename_id, { details = true })[3].invalid ~= true,
    "Rename invalidated the ID"
  )
  api.nvim_buf_set_lines(buf, row + 1, row + 2, false, {})
  api.nvim_buf_set_lines(buf, row + 1, row + 1, false, { "  inserted-benchmark.txt" })
  local expected_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local expected_capture = capture(buf, painter, ex.store, ex.root_path, 2)
  assert(
    vim.tbl_count(expected_capture.moves) == 1
      and vim.tbl_count(expected_capture.deletes) == 1
      and #expected_capture.creates == 1,
    "Expected one rename, delete, and insert"
  )
  local function verify()
    assert(vim.bo[buf].modified, "Lost modified state")
    assert(
      vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), expected_lines),
      "Dirty text changed after toggle pair"
    )
    local current = capture(buf, painter, ex.store, ex.root_path, 2)
    assert(vim.deep_equal(current.moves, expected_capture.moves), "Renamed ID changed")
    assert(vim.deep_equal(current.deletes, expected_capture.deletes), "Deleted ID changed")
    assert(vim.deep_equal(current.creates, expected_capture.creates), "Inserted entry changed")
  end
  local function toggle(open, from_child)
    counts = { capture_calls = 0, capture_ms = 0, parse_ms = 0 }
    api.nvim_win_set_cursor(ex.window.winid, { not open and from_child and 2 or 1, 0 })
    local start = vim.uv.hrtime()
    action.dispatch(open and "select" or "collapse_node", ctx)
    assert(
      vim.wait(10000, function()
        return target.open == open
          and api.nvim_buf_line_count(buf) == (open and #expected_lines or #expected_lines - 100)
      end, 1),
      "toggle timeout"
    )
    vim.cmd("redraw")
    counts.total_ms = (vim.uv.hrtime() - start) / 1e6
    counts.direction = open and "expand" or "collapse"
    counts.cursor = from_child and "child" or "directory"
    return vim.deepcopy(counts)
  end
  local result = { ui = api.nvim_list_uis(), version = vim.version(), fixture = fixture, samples = {} }
  for _, from_child in ipairs({ false, true }) do
    for repetition = 1, 5 do
      active = false
      for _ = 1, 5 do
        toggle(false, from_child)
        toggle(true, from_child)
      end
      verify()
      for _ = 1, 20 do
        active = true
        local collapse, expand = toggle(false, from_child), toggle(true, from_child)
        active = false
        collapse.repetition, expand.repetition = repetition, repetition
        result.samples[#result.samples + 1] = collapse
        result.samples[#result.samples + 1] = expand
        verify()
      end
    end
  end
  vim.fn.writefile({ vim.json.encode(result) }, output)
  eda.close()
end
vim.schedule(function()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    vim.fn.writefile({ tostring(err) }, output .. ".error")
    vim.cmd("cquit 1")
  end
  vim.cmd("qa!")
end)
