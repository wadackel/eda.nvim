local eda = require("eda")

local T = MiniTest.new_set()

-- Every mode `vim.fn.mode(1)` can report while an eda window is current, with whether
-- the replace overlay must step aside for it. Text input and selection hide the
-- overlay; command line, terminal and operator-pending do not.
local cases = {
  { mode = "n", hides = false, why = "normal" },
  { mode = "no", hides = false, why = "operator pending" },
  { mode = "nov", hides = false, why = "operator pending, forced charwise" },
  { mode = "i", hides = true, why = "insert" },
  { mode = "ic", hides = true, why = "insert, completion popup" },
  { mode = "ix", hides = true, why = "insert, ctrl-x completion" },
  { mode = "R", hides = true, why = "replace" },
  { mode = "Rc", hides = true, why = "replace, completion popup" },
  { mode = "Rv", hides = true, why = "virtual replace via gR" },
  { mode = "v", hides = true, why = "visual charwise" },
  { mode = "V", hides = true, why = "visual linewise" },
  { mode = "\22", hides = true, why = "visual blockwise" },
  { mode = "s", hides = true, why = "select charwise" },
  { mode = "S", hides = true, why = "select linewise" },
  { mode = "\19", hides = true, why = "select blockwise" },
  { mode = "niI", hides = true, why = "insert suspended by i_CTRL-O" },
  { mode = "niR", hides = true, why = "replace suspended by i_CTRL-O" },
  { mode = "niV", hides = true, why = "virtual replace suspended by i_CTRL-O" },
  { mode = "c", hides = false, why = "command line" },
  { mode = "cv", hides = false, why = "ex mode" },
  { mode = "t", hides = false, why = "terminal job" },
  { mode = "nt", hides = false, why = "terminal normal" },
}

for _, case in ipairs(cases) do
  T[string.format("mode_hides_overlay %q (%s)", case.mode, case.why)] = function()
    MiniTest.expect.equality(eda._mode_hides_overlay(case.mode), case.hides)
  end
end

-- The classifier reads mode(1) rather than matching ModeChanged patterns because those
-- fire on leaving a mode; this pins the leading-character rule the two share.
T["mode_hides_overlay distinguishes normal from its insert-suspended variants"] = function()
  MiniTest.expect.equality(eda._mode_hides_overlay("n"), false)
  MiniTest.expect.equality(eda._mode_hides_overlay("niI"), true)
end

return T
