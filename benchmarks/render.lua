-- Benchmark script for eda.nvim render pipeline
-- Usage: nvim --headless -l benchmarks/render.lua [target_dir]
--
-- Measures synchronous render pipeline (Lua + nvim API overhead).
-- Does NOT measure vim.schedule latency or screen draw cost.

vim.o.shadafile = "NONE"

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local Store = require("eda.tree.store")
local Scanner = require("eda.tree.scanner")
local Flatten = require("eda.render.flatten")
local Painter = require("eda.render.painter")
local decorator_mod = require("eda.render.decorator")
local config = require("eda.config")

local WARMUP = 5
local ITERATIONS = 20

-- Parse target directory from vim.v.argv (args after the script path)
local target_dir = nil
do
  local argv = vim.v.argv
  local found_script = false
  for _, arg in ipairs(argv) do
    if found_script and arg:sub(1, 1) ~= "-" then
      target_dir = arg
      break
    end
    if arg:match("render%.lua$") then
      found_script = true
    end
  end
end
if not target_dir or target_dir == "" then
  target_dir = vim.fn.getcwd()
end
target_dir = vim.fn.fnamemodify(target_dir, ":p"):gsub("/$", "")

-- Synchronous directory scan (blocking wrapper around async scanner)
local function scan_sync(scanner, node_id)
  local done = false
  scanner:scan(node_id, function()
    done = true
  end)
  vim.wait(10000, function()
    return done
  end)
end

-- Scan all directories recursively (synchronous)
local function scan_all_sync(scanner, store, node_id, depth)
  if depth > 5 then
    return
  end
  scan_sync(scanner, node_id)
  local node = store:get(node_id)
  if not node or not node.children_ids then
    return
  end
  for _, child_id in ipairs(node.children_ids) do
    local child = store:get(child_id)
    if child and child.type == "directory" then
      child.open = true
      scan_all_sync(scanner, store, child_id, depth + 1)
    end
  end
end

-- Build a render pipeline similar to render_with_decorators()
local function build_pipeline(root_path)
  local cfg = config.get()
  local store = Store.new()
  store:set_root(root_path)

  local scanner = Scanner.new(store, cfg)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  local painter = Painter.new(bufnr, cfg.indent.width)

  local chain = decorator_mod.Chain.new()
  chain:add(decorator_mod.icon_decorator)
  chain:add(decorator_mod.git_decorator)
  chain:add(decorator_mod.cut_decorator)

  return {
    store = store,
    scanner = scanner,
    bufnr = bufnr,
    painter = painter,
    chain = chain,
    cfg = cfg,
    root_path = root_path,
  }
end

-- Execute one full render cycle (flatten → decorate → paint)
local function render_once(p)
  local flat_lines = Flatten.flatten(p.store, p.store.root_id)
  local ctx = { store = p.store, git_status = nil, config = p.cfg }
  local decorations = p.chain:decorate(flat_lines, ctx)
  p.painter:paint(flat_lines, decorations, {
    root_path = p.root_path,
    header = p.cfg.header,
    kind = "split_left",
    icon = p.cfg.icon,
  })
  return #flat_lines
end

-- Execute one render cycle with per-phase timing breakdown
local function render_once_profiled(p)
  local t0 = vim.uv.hrtime()
  local flat_lines = Flatten.flatten(p.store, p.store.root_id)
  local t1 = vim.uv.hrtime()
  local ctx = { store = p.store, git_status = nil, config = p.cfg }
  local decorations = p.chain:decorate(flat_lines, ctx)
  local t2 = vim.uv.hrtime()
  p.painter:paint(flat_lines, decorations, {
    root_path = p.root_path,
    header = p.cfg.header,
    kind = "split_left",
    icon = p.cfg.icon,
  })
  local t3 = vim.uv.hrtime()
  return #flat_lines, (t1 - t0) / 1e6, (t2 - t1) / 1e6, (t3 - t2) / 1e6
end

-- Reset painter state to force full paint on next render
local function reset_painter(p)
  vim.api.nvim_buf_set_lines(p.bufnr, 0, -1, false, {})
  p.painter._decoration_cache = {}
  p.painter._flat_lines = {}
  p.painter.snapshot = { entries = {} }
end

-- Run a benchmark scenario
local function bench(name, setup_fn, p)
  if setup_fn then
    setup_fn(p)
  end

  local line_count = 0

  -- Warmup
  for _ = 1, WARMUP do
    reset_painter(p)
    collectgarbage("collect")
    render_once(p)
  end

  -- Measure
  local times = {}
  local mem_deltas = {}
  for i = 1, ITERATIONS do
    reset_painter(p)
    collectgarbage("collect")
    local mem_before = collectgarbage("count")
    local t0 = vim.uv.hrtime()
    line_count = render_once(p)
    local t1 = vim.uv.hrtime()
    local mem_after = collectgarbage("count")
    times[i] = (t1 - t0) / 1e6 -- ms
    mem_deltas[i] = mem_after - mem_before -- KB
  end

  -- Average
  local sum_t, sum_m = 0, 0
  for i = 1, ITERATIONS do
    sum_t = sum_t + times[i]
    sum_m = sum_m + mem_deltas[i]
  end
  local avg_t = sum_t / ITERATIONS
  local avg_m = sum_m / ITERATIONS

  print(string.format("  %-40s %8.3f ms  %8.1f KB  (%d lines)", name, avg_t, avg_m, line_count))
end

-- Main
print("eda.nvim Render Benchmark")
print(string.format("Target: %s", target_dir))
print(string.format("Iterations: %d (warmup: %d)", ITERATIONS, WARMUP))
print("")

local p = build_pipeline(target_dir)

-- Scenario 1: Initial render (root only expanded)
print("Scenario 1: Root only expanded")
scan_sync(p.scanner, p.store.root_id)
bench("render", nil, p)
print("")

-- Scenario 2: All directories expanded
print("Scenario 2: All directories expanded")
local root = p.store:get(p.store.root_id)
root.open = true
scan_all_sync(p.scanner, p.store, p.store.root_id, 0)
-- Mark all directories as open
for _, node in pairs(p.store.nodes) do
  if node.type == "directory" then
    node.open = true
  end
end
bench("render", nil, p)
print("")

-- Scenario 3: Directory toggle (re-render after toggle)
print("Scenario 3: Post-toggle render (dirty state)")
bench("render", function(pipeline)
  -- Toggle a directory to simulate a dirty state
  local first_dir = nil
  for _, node in pairs(pipeline.store.nodes) do
    if node.type == "directory" and node.id ~= pipeline.store.root_id and node.open then
      first_dir = node
      break
    end
  end
  if first_dir then
    first_dir.open = not first_dir.open
    first_dir.open = not first_dir.open -- toggle back to original state
  end
end, p)

-- Scenario 4: Decoration-only re-render (no reset, differential update)
print("Scenario 4: Decoration-only re-render (no reset, diff update)")
do
  -- First do a full render to establish baseline state
  reset_painter(p)
  render_once(p)

  local line_count = 0

  -- Warmup (re-renders without reset)
  for _ = 1, WARMUP do
    collectgarbage("collect")
    render_once(p)
  end

  -- Measure re-renders without reset (should use diff path)
  local times = {}
  local mem_deltas = {}
  for i = 1, ITERATIONS do
    collectgarbage("collect")
    local mem_before = collectgarbage("count")
    local t0 = vim.uv.hrtime()
    line_count = render_once(p)
    local t1 = vim.uv.hrtime()
    local mem_after = collectgarbage("count")
    times[i] = (t1 - t0) / 1e6
    mem_deltas[i] = mem_after - mem_before
  end

  local sum_t, sum_m = 0, 0
  for i = 1, ITERATIONS do
    sum_t = sum_t + times[i]
    sum_m = sum_m + mem_deltas[i]
  end
  print(
    string.format(
      "  %-40s %8.3f ms  %8.1f KB  (%d lines)",
      "re-render (no changes)",
      sum_t / ITERATIONS,
      sum_m / ITERATIONS,
      line_count
    )
  )
end
print("")

-- Scenario 5: Render with window (measures decoration provider effect)
print("Scenario 5: Render with window (decoration provider active)")
do
  -- Show buffer in a window so decoration provider fires for visible lines
  vim.api.nvim_set_current_buf(p.bufnr)
  -- Force a small viewport to simulate typical sidebar width
  vim.cmd("redraw")

  local line_count = 0

  -- Warmup
  for _ = 1, WARMUP do
    reset_painter(p)
    p.painter._flat_lines = {}
    p.painter._line_lengths = {}

    collectgarbage("collect")
    render_once(p)
    vim.cmd("redraw")
  end

  -- Measure
  local times = {}
  local mem_deltas = {}
  for i = 1, ITERATIONS do
    reset_painter(p)
    p.painter._flat_lines = {}
    p.painter._line_lengths = {}

    collectgarbage("collect")
    local mem_before = collectgarbage("count")
    local t0 = vim.uv.hrtime()
    line_count = render_once(p)
    vim.cmd("redraw")
    local t1 = vim.uv.hrtime()
    local mem_after = collectgarbage("count")
    times[i] = (t1 - t0) / 1e6
    mem_deltas[i] = mem_after - mem_before
  end

  local sum_t, sum_m = 0, 0
  for i = 1, ITERATIONS do
    sum_t = sum_t + times[i]
    sum_m = sum_m + mem_deltas[i]
  end
  print(
    string.format(
      "  %-40s %8.3f ms  %8.1f KB  (%d lines)",
      "render + redraw (with window)",
      sum_t / ITERATIONS,
      sum_m / ITERATIONS,
      line_count
    )
  )
end
print("")

-- Scenario 6: Re-render with window (no changes, provider-only cost)
print("Scenario 6: Re-render with window (no changes, provider-only)")
do
  -- Establish state
  reset_painter(p)
  p.painter._flat_lines = {}
  p.painter._line_lengths = {}
  p.painter._prev_node_ids = {}
  render_once(p)
  vim.cmd("redraw")

  local line_count = 0

  -- Warmup
  for _ = 1, WARMUP do
    collectgarbage("collect")
    render_once(p)
    vim.cmd("redraw")
  end

  -- Measure
  local times = {}
  local mem_deltas = {}
  for i = 1, ITERATIONS do
    collectgarbage("collect")
    local mem_before = collectgarbage("count")
    local t0 = vim.uv.hrtime()
    line_count = render_once(p)
    vim.cmd("redraw")
    local t1 = vim.uv.hrtime()
    local mem_after = collectgarbage("count")
    times[i] = (t1 - t0) / 1e6
    mem_deltas[i] = mem_after - mem_before
  end

  local sum_t, sum_m = 0, 0
  for i = 1, ITERATIONS do
    sum_t = sum_t + times[i]
    sum_m = sum_m + mem_deltas[i]
  end
  print(
    string.format(
      "  %-40s %8.3f ms  %8.1f KB  (%d lines)",
      "re-render + redraw (no changes)",
      sum_t / ITERATIONS,
      sum_m / ITERATIONS,
      line_count
    )
  )
end
print("")

-- Scenario 7: Single directory toggle (expand_all → close one dir → render → open → render)
print("Scenario 7: Single directory toggle (profiled breakdown)")
do
  -- Find a directory with children to toggle
  local toggle_node = nil
  for _, node in pairs(p.store.nodes) do
    if
      node.type == "directory"
      and node.id ~= p.store.root_id
      and node.open
      and node.children_ids
      and #node.children_ids > 10
    then
      toggle_node = node
      break
    end
  end

  if toggle_node then
    -- Establish baseline state (all expanded, rendered)
    reset_painter(p)
    render_once(p)

    -- Warmup
    for _ = 1, WARMUP do
      toggle_node.open = false
      reset_painter(p)
      render_once(p)
      toggle_node.open = true
      reset_painter(p)
      render_once(p)
    end

    -- Measure collapse
    local collapse_times = { total = {}, flatten = {}, decorate = {}, paint = {} }
    local expand_times = { total = {}, flatten = {}, decorate = {}, paint = {} }
    local collapse_lines, expand_lines = 0, 0

    for i = 1, ITERATIONS do
      -- Collapse
      toggle_node.open = false
      reset_painter(p)
      collectgarbage("collect")
      local t0 = vim.uv.hrtime()
      local lines, ft, dt, pt = render_once_profiled(p)
      local t1 = vim.uv.hrtime()
      collapse_lines = lines
      collapse_times.total[i] = (t1 - t0) / 1e6
      collapse_times.flatten[i] = ft
      collapse_times.decorate[i] = dt
      collapse_times.paint[i] = pt

      -- Expand
      toggle_node.open = true
      reset_painter(p)
      collectgarbage("collect")
      t0 = vim.uv.hrtime()
      lines, ft, dt, pt = render_once_profiled(p)
      t1 = vim.uv.hrtime()
      expand_lines = lines
      expand_times.total[i] = (t1 - t0) / 1e6
      expand_times.flatten[i] = ft
      expand_times.decorate[i] = dt
      expand_times.paint[i] = pt
    end

    local function avg(t)
      local sum = 0
      for _, v in ipairs(t) do
        sum = sum + v
      end
      return sum / #t
    end

    print(string.format("  Toggle target: %s (%d children)", toggle_node.name, #toggle_node.children_ids))
    print(
      string.format(
        "  %-40s %8.3f ms  (flatten: %6.3f  decorate: %6.3f  paint: %6.3f)  (%d lines)",
        "collapse",
        avg(collapse_times.total),
        avg(collapse_times.flatten),
        avg(collapse_times.decorate),
        avg(collapse_times.paint),
        collapse_lines
      )
    )
    print(
      string.format(
        "  %-40s %8.3f ms  (flatten: %6.3f  decorate: %6.3f  paint: %6.3f)  (%d lines)",
        "expand",
        avg(expand_times.total),
        avg(expand_times.flatten),
        avg(expand_times.decorate),
        avg(expand_times.paint),
        expand_lines
      )
    )
  else
    print("  (no suitable directory found for toggle test)")
  end
end
print("")

-- Scenario 8: Edit-preserve capture pipeline (dirty buffer, profiled breakdown)
print("Scenario 8: Edit-preserve capture (dirty buffer, profiled)")
do
  local Parser = require("eda.buffer.parser")
  local edit_preserve = require("eda.buffer.edit_preserve")

  -- Establish clean state with full render
  reset_painter(p)
  render_once(p)

  -- Simulate dirty buffer:
  -- 1. INSERT a new line (CREATE op)
  local offset = p.painter.header_lines or 0
  vim.api.nvim_buf_set_lines(p.bufnr, offset + 1, offset + 1, false, { "  new_file.txt" })
  -- 2. RENAME an existing line (MOVE op): change the text without disturbing extmarks
  local rename_row = offset + 3
  local old_lines = vim.api.nvim_buf_get_lines(p.bufnr, rename_row, rename_row + 1, false)
  if old_lines[1] then
    local renamed = old_lines[1]:gsub("[^/%s]+$", "renamed_entry")
    vim.api.nvim_buf_set_lines(p.bufnr, rename_row, rename_row + 1, false, { renamed })
  end
  vim.bo[p.bufnr].modified = true

  local line_count = vim.api.nvim_buf_line_count(p.bufnr)

  -- Profiled capture: measure parse_lines, Diff.compute, and operation loop separately
  local function capture_profiled()
    local ns_id = p.painter.ns_ids
    local header_lines = p.painter.header_lines or 0

    local t0 = vim.uv.hrtime()
    local parsed = Parser.parse_lines(p.bufnr, ns_id, p.cfg.indent.width, p.root_path, header_lines)
    local t1 = vim.uv.hrtime()

    local snapshot = p.painter:get_snapshot()
    local Diff = require("eda.tree.diff")
    local operations = Diff.compute(parsed, snapshot, p.store)
    local t2 = vim.uv.hrtime()

    -- Operation loop (build moves/deletes/creates)
    local index_by_node_id = {}
    for i, pl in ipairs(parsed) do
      if pl.node_id then
        index_by_node_id[pl.node_id] = i
      end
    end
    local snap_path_to_id = {}
    for node_id, entry in pairs(snapshot.entries) do
      snap_path_to_id[entry.path] = node_id
    end
    local moves = {}
    local deletes = {}
    for _, op in ipairs(operations) do
      if op.type == "move" then
        local nid = snap_path_to_id[op.src]
        if nid then
          local idx = index_by_node_id[nid]
          if idx then
            local row = header_lines + idx - 1
            local line = vim.api.nvim_buf_get_lines(p.bufnr, row, row + 1, false)[1]
            if line then
              moves[nid] = line
            end
          end
        end
      elseif op.type == "delete" then
        local nid = snap_path_to_id[op.path]
        if nid then
          deletes[nid] = true
        end
      end
    end
    local t3 = vim.uv.hrtime()

    return (t1 - t0) / 1e6, (t2 - t1) / 1e6, (t3 - t2) / 1e6
  end

  -- Warmup
  for _ = 1, WARMUP do
    collectgarbage("collect")
    capture_profiled()
  end

  -- Measure
  local times = { parse = {}, diff = {}, ops = {} }
  for i = 1, ITERATIONS do
    collectgarbage("collect")
    local pt, dt, ot = capture_profiled()
    times.parse[i] = pt
    times.diff[i] = dt
    times.ops[i] = ot
  end

  local function avg(t)
    local sum = 0
    for _, v in ipairs(t) do
      sum = sum + v
    end
    return sum / #t
  end

  local avg_parse = avg(times.parse)
  local avg_diff = avg(times.diff)
  local avg_ops = avg(times.ops)
  local avg_total = avg_parse + avg_diff + avg_ops
  print(
    string.format(
      "  %-40s %8.3f ms  (parse: %6.3f  diff: %6.3f  ops: %6.3f)  (%d lines)",
      "capture (dirty buffer)",
      avg_total,
      avg_parse,
      avg_diff,
      avg_ops,
      line_count
    )
  )

  -- Also measure full capture() for comparison
  local capture_times = {}
  for _ = 1, WARMUP do
    collectgarbage("collect")
    edit_preserve.capture(p.bufnr, p.painter, p.store, p.root_path, p.cfg.indent.width)
  end
  for i = 1, ITERATIONS do
    collectgarbage("collect")
    local t0 = vim.uv.hrtime()
    edit_preserve.capture(p.bufnr, p.painter, p.store, p.root_path, p.cfg.indent.width)
    local t1 = vim.uv.hrtime()
    capture_times[i] = (t1 - t0) / 1e6
  end
  print(string.format("  %-40s %8.3f ms", "capture() full call", avg(capture_times)))
end
print("")

-- Scenario 9: Incremental paint toggle (paint_incremental vs full paint)
print("Scenario 9: Incremental paint toggle")
do
  local Flatten = require("eda.render.flatten")

  -- Find a directory with children to toggle
  local toggle_node = nil
  for _, node in pairs(p.store.nodes) do
    if
      node.type == "directory"
      and node.id ~= p.store.root_id
      and node.open
      and node.children_ids
      and #node.children_ids > 10
    then
      toggle_node = node
      break
    end
  end

  if toggle_node then
    local function avg(t)
      local sum = 0
      for _, v in ipairs(t) do
        sum = sum + v
      end
      return sum / #t
    end

    -- Measure full paint toggle
    local full_collapse_times = {}
    local full_expand_times = {}
    for _ = 1, WARMUP do
      toggle_node.open = false
      reset_painter(p)
      render_once(p)
      toggle_node.open = true
      reset_painter(p)
      render_once(p)
    end
    for i = 1, ITERATIONS do
      toggle_node.open = false
      reset_painter(p)
      collectgarbage("collect")
      local t0 = vim.uv.hrtime()
      render_once(p)
      local t1 = vim.uv.hrtime()
      full_collapse_times[i] = (t1 - t0) / 1e6

      toggle_node.open = true
      reset_painter(p)
      collectgarbage("collect")
      t0 = vim.uv.hrtime()
      render_once(p)
      t1 = vim.uv.hrtime()
      full_expand_times[i] = (t1 - t0) / 1e6
    end

    -- Measure incremental paint toggle
    local incr_collapse_times = {}
    local incr_expand_times = {}
    -- Establish state with full paint (open)
    toggle_node.open = true
    reset_painter(p)
    render_once(p)
    for _ = 1, WARMUP do
      toggle_node.open = false
      local fl = Flatten.flatten(p.store, p.store.root_id)
      local decs = p.chain:decorate(fl, { store = p.store, config = p.cfg })
      p.painter:paint_incremental(fl, decs, { icon = p.cfg.icon }, { toggled_node_id = toggle_node.id })
      toggle_node.open = true
      fl = Flatten.flatten(p.store, p.store.root_id)
      decs = p.chain:decorate(fl, { store = p.store, config = p.cfg })
      p.painter:paint_incremental(fl, decs, { icon = p.cfg.icon }, { toggled_node_id = toggle_node.id })
    end
    for i = 1, ITERATIONS do
      toggle_node.open = false
      local fl = Flatten.flatten(p.store, p.store.root_id)
      local decs = p.chain:decorate(fl, { store = p.store, config = p.cfg })
      collectgarbage("collect")
      local t0 = vim.uv.hrtime()
      p.painter:paint_incremental(fl, decs, { icon = p.cfg.icon }, { toggled_node_id = toggle_node.id })
      local t1 = vim.uv.hrtime()
      incr_collapse_times[i] = (t1 - t0) / 1e6

      toggle_node.open = true
      fl = Flatten.flatten(p.store, p.store.root_id)
      decs = p.chain:decorate(fl, { store = p.store, config = p.cfg })
      collectgarbage("collect")
      t0 = vim.uv.hrtime()
      p.painter:paint_incremental(fl, decs, { icon = p.cfg.icon }, { toggled_node_id = toggle_node.id })
      t1 = vim.uv.hrtime()
      incr_expand_times[i] = (t1 - t0) / 1e6
    end

    print(string.format("  Toggle target: %s (%d children)", toggle_node.name, #toggle_node.children_ids))
    print(string.format("  %-40s %8.3f ms", "full paint collapse", avg(full_collapse_times)))
    print(string.format("  %-40s %8.3f ms", "incremental collapse", avg(incr_collapse_times)))
    print(string.format("  %-40s %8.3f ms", "full paint expand", avg(full_expand_times)))
    print(string.format("  %-40s %8.3f ms", "incremental expand", avg(incr_expand_times)))
    local speedup_c = avg(full_collapse_times) / avg(incr_collapse_times)
    local speedup_e = avg(full_expand_times) / avg(incr_expand_times)
    print(string.format("  Speedup: collapse %.1fx, expand %.1fx", speedup_c, speedup_e))
  else
    print("  (no suitable directory found for toggle test)")
  end
end
print("")

-- Cleanup
vim.api.nvim_buf_delete(p.bufnr, { force = true })

print("Done.")
vim.cmd("qa!")
