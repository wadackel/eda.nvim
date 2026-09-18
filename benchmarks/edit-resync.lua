vim.o.shadafile = "NONE"
vim.o.more = false
vim.opt.rtp:prepend(vim.fn.getcwd())
local fixture = assert(vim.env.EDA_BENCH_DIR, "Set EDA_BENCH_DIR to a 100 x 100 file fixture")
local output = assert(vim.env.EDA_BENCH_OUTPUT, "Set EDA_BENCH_OUTPUT to the output JSON path")
local api = vim.api
local counts, active, ex = {}, false, nil
local set_mark, del_mark, clear = api.nvim_buf_set_extmark, api.nvim_buf_del_extmark, api.nvim_buf_clear_namespace
api.nvim_buf_set_extmark = function(buf, ns, ...)
	if active and ns == ex.buffer.painter.ns_icon then
		counts.icon_writes = counts.icon_writes + 1
	end
	return set_mark(buf, ns, ...)
end
api.nvim_buf_del_extmark = function(buf, ns, ...)
	if active and ns == ex.buffer.painter.ns_icon then
		counts.icon_deletes = counts.icon_deletes + 1
	end
	return del_mark(buf, ns, ...)
end
api.nvim_buf_clear_namespace = function(buf, ns, ...)
	if active and ns == ex.buffer.painter.ns_icon then
		counts.icon_clears = counts.icon_clears + 1
	end
	return clear(buf, ns, ...)
end
local function cpu_ms()
	local usage = vim.uv.getrusage()
	return (usage.utime.sec + usage.stime.sec) * 1e3 + (usage.utime.usec + usage.stime.usec) / 1e3
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
		icon = {
			provider = "none",
			custom = function(_, node)
				if node.type == "file" then
					return "f", "EdaFileIcon"
				end
			end,
			directory = { collapsed = "+", expanded = "-", empty = "+", empty_open = "-" },
		},
	})
	eda.open({ dir = fixture })
	assert(
		vim.wait(10000, function()
			return eda.get_current() and eda.get_current()._initial_scan_complete
		end, 1),
		"initial scan timeout"
	)
	ex = eda.get_current()
	local ctx = {
		explorer = ex,
		store = ex.store,
		scanner = ex.scanner,
		buffer = ex.buffer,
		window = ex.window,
		config = require("eda.config").get(),
	}
	require("eda.action").dispatch("expand_all", ctx)
	assert(
		vim.wait(10000, function()
			return #ex.buffer.flat_lines == 10100
		end, 1),
		"expand timeout"
	)
	local buf, painter, win = ex.buffer.bufnr, ex.buffer.painter, ex.window.winid
	local expected = api.nvim_buf_get_lines(buf, 0, -1, false)
	local function icon_rows()
		local rows = {}
		for _, m in ipairs(api.nvim_buf_get_extmarks(buf, painter.ns_icon, 0, -1, {})) do
			rows[#rows + 1] = m[2]
		end
		return rows
	end
	local baseline_icons = icon_rows()
	local function resync(kind)
		counts = { icon_writes = 0, icon_deletes = 0, icon_clears = 0 }
		active = true
		local cpu_start = cpu_ms()
		local start = vim.uv.hrtime()
		painter:resync_highlights()
		counts.total_ms = (vim.uv.hrtime() - start) / 1e6
		counts.cpu_ms = cpu_ms() - cpu_start
		active = false
		counts.direction = kind
		return vim.deepcopy(counts)
	end
	-- Row 5,000 of 10,100: a file halfway down, so every later icon has shifted.
	local row = 5000
	local function pair()
		api.nvim_win_set_cursor(win, { row, 0 })
		vim.cmd("normal! dd")
		local deleted = resync("dd")
		assert(#icon_rows() == #baseline_icons - 1, "dd left a stale icon")
		vim.cmd("silent undo")
		local undone = resync("undo")
		assert(vim.deep_equal(icon_rows(), baseline_icons), "undo did not restore the icons")
		assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), expected), "undo did not restore the text")
		return deleted, undone
	end
	local result = { ui = api.nvim_list_uis(), version = vim.version(), fixture = fixture, samples = {} }
	for repetition = 1, 5 do
		for _ = 1, 5 do
			pair()
		end
		for _ = 1, 20 do
			local deleted, undone = pair()
			deleted.repetition, undone.repetition = repetition, repetition
			result.samples[#result.samples + 1] = deleted
			result.samples[#result.samples + 1] = undone
		end
	end
	vim.fn.writefile({ vim.json.encode(result) }, output)
	vim.bo[buf].modified = false
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
