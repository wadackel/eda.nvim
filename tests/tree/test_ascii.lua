local ascii = require("eda.tree.ascii")
local Node = require("eda.tree.node")

local T = MiniTest.new_set()

local next_id = 0
local function node(name, path, type)
  next_id = next_id + 1
  return Node.create({ id = next_id, name = name, path = path, type = type or "file" })
end

T["render"] = MiniTest.new_set()

T["render"]["empty input returns empty string"] = function()
  MiniTest.expect.equality(ascii.render({}, "/r"), "")
end

T["render"]["single file short-circuits to relative path without tree glyphs"] = function()
  local n = node("foo.ts", "/r/src/foo.ts", "file")
  MiniTest.expect.equality(ascii.render({ n }, "/r"), "src/foo.ts")
end

T["render"]["single directory short-circuits to relative path with trailing slash"] = function()
  local n = node("src", "/r/src", "directory")
  MiniTest.expect.equality(ascii.render({ n }, "/r"), "src/")
end

T["render"]["single root-direct file returns just the name"] = function()
  local n = node("README.md", "/r/README.md", "file")
  MiniTest.expect.equality(ascii.render({ n }, "/r"), "README.md")
end

T["render"]["canonical example: dir + child + sibling"] = function()
  -- input: [src/, src/foo.ts, tests/bar.ts]
  -- common ancestor = explorer root → "./" header
  -- src/ is explicit AND a parent of selected child → rendered once as branch
  local src_dir = node("src", "/r/src", "directory")
  local foo_ts = node("foo.ts", "/r/src/foo.ts", "file")
  local bar_ts = node("bar.ts", "/r/tests/bar.ts", "file")

  local expected = table.concat({
    "./",
    "├── src/",
    "│   └── foo.ts",
    "└── tests/",
    "    └── bar.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ src_dir, foo_ts, bar_ts }, "/r"), expected)
end

T["render"]["common ancestor is non-root directory"] = function()
  -- input: [src/foo.ts, src/bar.ts] → header is "src/" not "./"
  local foo_ts = node("foo.ts", "/r/src/foo.ts", "file")
  local bar_ts = node("bar.ts", "/r/src/bar.ts", "file")

  local expected = table.concat({
    "src/",
    "├── bar.ts",
    "└── foo.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ foo_ts, bar_ts }, "/r"), expected)
end

T["render"]["directories only as leaves"] = function()
  local src = node("src", "/r/src", "directory")
  local tests_dir = node("tests", "/r/tests", "directory")

  local expected = table.concat({
    "./",
    "├── src/",
    "└── tests/",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ src, tests_dir }, "/r"), expected)
end

T["render"]["symlink rendered without suffix"] = function()
  local link = node("alias.lua", "/r/src/alias.lua", "link")
  local plain = node("foo.ts", "/r/src/foo.ts", "file")

  local expected = table.concat({
    "src/",
    "├── alias.lua",
    "└── foo.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ link, plain }, "/r"), expected)
end

T["render"]["mixed dir+file siblings: directories first then natural sort"] = function()
  -- siblings under root: z.ts, a.ts (files), m/ src/ (dirs)
  -- expected order: m/, src/, a.ts, z.ts (dirs-first, natural sort within group)
  local z = node("z.ts", "/r/z.ts", "file")
  local a = node("a.ts", "/r/a.ts", "file")
  local m = node("m", "/r/m", "directory")
  local src = node("src", "/r/src", "directory")

  local expected = table.concat({
    "./",
    "├── m/",
    "├── src/",
    "├── a.ts",
    "└── z.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ z, a, m, src }, "/r"), expected)
end

T["render"]["natural sort handles numeric segments"] = function()
  -- file1, file2, file10 (numeric order, not lexical "file1 < file10 < file2")
  local f10 = node("file10.ts", "/r/file10.ts", "file")
  local f2 = node("file2.ts", "/r/file2.ts", "file")
  local f1 = node("file1.ts", "/r/file1.ts", "file")

  local expected = table.concat({
    "./",
    "├── file1.ts",
    "├── file2.ts",
    "└── file10.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ f10, f2, f1 }, "/r"), expected)
end

T["render"]["explicit dir + its child renders dir only once"] = function()
  -- regression for the canonical decision: dir appears as branch, not duplicated as leaf
  local src = node("src", "/r/src", "directory")
  local foo = node("foo.ts", "/r/src/foo.ts", "file")

  -- common ancestor is "src" → header "src/", child "foo.ts" as leaf
  local expected = table.concat({
    "src/",
    "└── foo.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ src, foo }, "/r"), expected)
end

T["render"]["deeply nested scaffolding"] = function()
  -- input: [src/a/b/c.ts, src/a/b/d.ts, src/x.ts]
  -- common ancestor = src/
  local c = node("c.ts", "/r/src/a/b/c.ts", "file")
  local d = node("d.ts", "/r/src/a/b/d.ts", "file")
  local x = node("x.ts", "/r/src/x.ts", "file")

  local expected = table.concat({
    "src/",
    "├── a/",
    "│   └── b/",
    "│       ├── c.ts",
    "│       └── d.ts",
    "└── x.ts",
  }, "\n")
  MiniTest.expect.equality(ascii.render({ c, d, x }, "/r"), expected)
end

return T
