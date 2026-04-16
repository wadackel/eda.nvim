local decorator = require("eda.render.decorator")
local Node = require("eda.tree.node")
local config = require("eda.config")

local T = MiniTest.new_set()

-- =============================================
-- Chain tests (existing, unchanged)
-- =============================================

T["Chain new creates empty chain"] = function()
  local chain = decorator.Chain.new()
  MiniTest.expect.equality(#chain.decorators, 0)
end

T["Chain add appends decorator"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { icon = "X" }
  end)
  MiniTest.expect.equality(#chain.decorators, 1)
end

T["Chain decorate applies decorators sequentially"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { icon = "A", suffix = "1" }
  end)
  chain:add(function()
    return { icon = "B" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(#result, 1)
  MiniTest.expect.equality(result[1].icon, "B") -- last wins
  MiniTest.expect.equality(result[1].suffix, "1") -- preserved from first
end

T["Chain decorate handles nil returns"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { icon = "A" }
  end)
  chain:add(function()
    return nil
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].icon, "A") -- nil doesn't clear
end

-- =============================================
-- T1: closed directory → directory.collapsed glyph
-- =============================================

T["T1 closed dir returns directory.collapsed glyph"] = function()
  config.setup()
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = "lib",
    path = "/lib",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, ctx.config.icon.directory.collapsed)
  MiniTest.expect.equality(dec.icon_hl, "EdaDirectoryIcon")
  MiniTest.expect.equality(dec.icon, "󰉋")
end

-- =============================================
-- T2: open directory → directory.expanded glyph
-- =============================================

T["T2 open dir returns directory.expanded glyph"] = function()
  config.setup()
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = "src",
    path = "/src",
    type = "directory",
    open = true,
    children_ids = { 2, 3 },
    children_state = "loaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, ctx.config.icon.directory.expanded)
  MiniTest.expect.equality(dec.icon_hl, "EdaDirectoryIcon")
  MiniTest.expect.equality(dec.icon, "󰝰")
end

-- =============================================
-- T3: empty+closed directory → directory.empty glyph
-- =============================================

T["T3 empty closed dir returns directory.empty glyph"] = function()
  config.setup()
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = "empty_dir",
    path = "/empty_dir",
    type = "directory",
    open = false,
    children_ids = {},
    children_state = "loaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "󰉖")
end

-- =============================================
-- T4: empty+open directory → directory.empty_open glyph
-- =============================================

T["T4 empty open dir returns directory.empty_open glyph"] = function()
  config.setup()
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = "empty_dir",
    path = "/empty_dir",
    type = "directory",
    open = true,
    children_ids = {},
    children_state = "loaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  -- NEW: empty_open should be reachable
  MiniTest.expect.equality(dec.icon, "󰷏")
end

-- =============================================
-- T5: provider=mini_icons → file icon from mini.icons
-- =============================================

T["T5 mini_icons provider returns file icon"] = function()
  config.setup({ icon = { provider = "mini_icons" } })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "init.lua", path = "/init.lua", type = "file" })
  local dec = decorator.icon_decorator(node, ctx)
  -- mini.icons should be available in test environment (via mini.nvim)
  -- If not available, decorator should fall back gracefully
  if dec then
    MiniTest.expect.equality(type(dec.icon), "string")
    MiniTest.expect.equality(#dec.icon > 0, true)
    MiniTest.expect.equality(type(dec.icon_hl), "string")
  end
end

-- =============================================
-- T7: no providers → nil for file
-- =============================================

T["T7 no provider returns nil for file"] = function()
  -- This test verifies behavior when neither provider is available
  -- We can't easily mock pcall failures, but we test the return type contract
  config.setup({ icon = { provider = "none" } })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "test.xyz", path = "/test.xyz", type = "file" })
  local dec = decorator.icon_decorator(node, ctx)
  -- With provider="none", neither mini_icons nor nvim_web_devicons dispatch path is taken
  -- The function should return nil (no icon for unknown provider)
  MiniTest.expect.equality(dec, nil)
end

-- =============================================
-- T9: config defaults are folder glyphs under nested directory table
-- =============================================

T["T9 config defaults use nested directory glyphs"] = function()
  config.setup()
  local c = config.get()
  MiniTest.expect.equality(c.icon.directory.collapsed, "󰉋")
  MiniTest.expect.equality(c.icon.directory.expanded, "󰝰")
  MiniTest.expect.equality(c.icon.directory.empty, "󰉖")
  MiniTest.expect.equality(c.icon.directory.empty_open, "󰷏")
  MiniTest.expect.equality(c.icon.provider, "mini_icons")
  MiniTest.expect.equality(c.icon.custom, nil)
end

-- =============================================
-- T10: custom overrides file icon
-- =============================================

T["T10 custom overrides file icon"] = function()
  config.setup({
    icon = {
      custom = function(_name, _node)
        return "X", "MyHl"
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "init.lua", path = "/init.lua", type = "file" })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "X")
  MiniTest.expect.equality(dec.icon_hl, "MyHl")
end

-- =============================================
-- T11: custom overrides directory icon
-- =============================================

T["T11 custom overrides directory icon"] = function()
  config.setup({
    icon = {
      custom = function(name, node)
        if node.type == "directory" and name == ".github" then
          return "G", "MyDirHl"
        end
        return nil
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = ".github",
    path = "/.github",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "G")
  MiniTest.expect.equality(dec.icon_hl, "MyDirHl")
end

-- =============================================
-- T12: custom nil fallback to provider
-- =============================================

T["T12 custom nil fallback to provider"] = function()
  config.setup({
    icon = {
      provider = "mini_icons",
      custom = function(_name, _node)
        return nil
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "init.lua", path = "/init.lua", type = "file" })
  local dec = decorator.icon_decorator(node, ctx)
  if dec then
    MiniTest.expect.equality(type(dec.icon), "string")
    MiniTest.expect.equality(#dec.icon > 0, true)
    MiniTest.expect.equality(type(dec.icon_hl), "string")
  end
end

-- =============================================
-- T13: custom nil fallback to directory
-- =============================================

T["T13 custom nil fallback to directory"] = function()
  config.setup({
    icon = {
      custom = function(_name, _node)
        return nil
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({
    id = 1,
    name = "lib",
    path = "/lib",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, ctx.config.icon.directory.collapsed)
  MiniTest.expect.equality(dec.icon_hl, "EdaDirectoryIcon")
end

-- =============================================
-- T14: custom error propagates (bare call policy)
-- =============================================

T["T14 custom error propagates"] = function()
  config.setup({
    icon = {
      custom = function(_name, _node)
        error("boom")
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "init.lua", path = "/init.lua", type = "file" })
  local ok, err = pcall(decorator.icon_decorator, node, ctx)
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(type(err) == "string" and err:find("boom", 1, true) ~= nil, true)
end

-- =============================================
-- T15: custom can return icon without hl
-- =============================================

T["T15 custom can return icon without hl"] = function()
  config.setup({
    icon = {
      custom = function(_name, _node)
        return "Y"
      end,
    },
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local node = Node.create({ id = 1, name = "init.lua", path = "/init.lua", type = "file" })
  local dec = decorator.icon_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "Y")
  MiniTest.expect.equality(dec.icon_hl, nil)
end

-- =============================================
-- Git decorator tests
-- =============================================

T["git_decorator sets name_hl for ignored file"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = { ["/f"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "◌")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
  MiniTest.expect.equality(dec.icon_hl, nil)
end

T["git_decorator sets name_hl for modified file"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = { ["/f"] = "M" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitModifiedIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitModifiedName")
  MiniTest.expect.equality(dec.icon_hl, nil)
end

T["git_decorator does not set name_hl for directory nodes"] = function()
  config.setup()
  local node = Node.create({
    id = 1,
    name = "dir",
    path = "/dir",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = { ["/dir"] = "M" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitModifiedIcon")
  MiniTest.expect.equality(dec.name_hl, nil)
  MiniTest.expect.equality(dec.icon_hl, nil)
end

T["git_decorator sets name_hl for ignored directory nodes"] = function()
  config.setup()
  local node = Node.create({
    id = 1,
    name = "target",
    path = "/target",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = { ["/target"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "◌")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["git_decorator inherits ignored status from parent directory"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "Main.class", path = "/target/classes/Main.class", type = "file" })
  local ctx = { store = {}, git_status = { ["/target"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["git_decorator inherits ignored status for deeply nested child"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f.txt", path = "/target/a/b/c/f.txt", type = "file" })
  local ctx = { store = {}, git_status = { ["/target"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["git_decorator inherits ignored status for child directory"] = function()
  config.setup()
  local node = Node.create({
    id = 1,
    name = "classes",
    path = "/target/classes",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = { ["/target"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["git_decorator does not inherit ignored for unrelated path"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "main.lua", path = "/src/main.lua", type = "file" })
  local ctx = { store = {}, git_status = { ["/target"] = "!" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["git_decorator returns nil without git_status"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["git_decorator returns default icons for each status"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })

  local expected = {
    ["?"] = { suffix = "", suffix_hl = "EdaGitUntrackedIcon", name_hl = "EdaGitUntrackedName" },
    ["A"] = { suffix = "", suffix_hl = "EdaGitAddedIcon", name_hl = "EdaGitAddedName" },
    ["M"] = { suffix = "", suffix_hl = "EdaGitModifiedIcon", name_hl = "EdaGitModifiedName" },
    ["R"] = { suffix = "", suffix_hl = "EdaGitRenamedIcon", name_hl = "EdaGitRenamedName" },
    ["C"] = { suffix = "", suffix_hl = "EdaGitStagedIcon", name_hl = "EdaGitStagedName" },
    ["U"] = { suffix = "", suffix_hl = "EdaGitConflictIcon", name_hl = "EdaGitConflictName" },
    ["!"] = { suffix = "◌", suffix_hl = "EdaGitIgnoredIcon", name_hl = "EdaGitIgnoredName" },
  }

  for status_code, exp in pairs(expected) do
    local ctx = { store = {}, git_status = { ["/f"] = status_code }, config = config.get() }
    local dec = decorator.git_decorator(node, ctx)
    MiniTest.expect.equality(dec.suffix, exp.suffix)
    MiniTest.expect.equality(dec.suffix_hl, exp.suffix_hl)
    MiniTest.expect.equality(dec.name_hl, exp.name_hl)
  end
end

T["git_decorator returns decoration for deleted status (default Nerd Font icon)"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = { ["/f"] = "D" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitDeletedIcon")
end

T["git_decorator uses custom icons from config"] = function()
  config.setup({
    git = {
      icons = {
        modified = "M",
        untracked = "U",
        added = "A",
      },
    },
  })
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })

  local ctx_m = { store = {}, git_status = { ["/f"] = "M" }, config = config.get() }
  local dec_m = decorator.git_decorator(node, ctx_m)
  MiniTest.expect.equality(dec_m.suffix, "M")

  local ctx_q = { store = {}, git_status = { ["/f"] = "?" }, config = config.get() }
  local dec_q = decorator.git_decorator(node, ctx_q)
  MiniTest.expect.equality(dec_q.suffix, "U")

  local ctx_a = { store = {}, git_status = { ["/f"] = "A" }, config = config.get() }
  local dec_a = decorator.git_decorator(node, ctx_a)
  MiniTest.expect.equality(dec_a.suffix, "A")
end

T["git_decorator hides icon when set to empty string"] = function()
  config.setup({
    git = {
      icons = {
        modified = "",
      },
    },
  })
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = { ["/f"] = "M" }, config = config.get() }
  local dec = decorator.git_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

-- =============================================
-- name_hl array accumulation tests
-- =============================================

T["Chain decorate accumulates name_hl as array from multiple decorators"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { name_hl = "HlA" }
  end)
  chain:add(function()
    return { name_hl = "HlB" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].name_hl, { "HlA", "HlB" })
end

T["Chain decorate keeps name_hl as string when only one decorator sets it"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { icon = "X" }
  end)
  chain:add(function()
    return { name_hl = "HlA" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(type(result[1].name_hl), "string")
  MiniTest.expect.equality(result[1].name_hl, "HlA")
end

T["Chain decorate leaves name_hl nil when no decorator sets it"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { icon = "X" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].name_hl, nil)
end

-- =============================================
-- .git (dotgit) decorator tests
-- =============================================

T["dotgit_decorator returns decoration for .git directory"] = function()
  config.setup()
  local node = Node.create({
    id = 1,
    name = ".git",
    path = "/project/.git",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "◌")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["dotgit_decorator returns decoration for child file inside .git/"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "HEAD", path = "/project/.git/HEAD", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "◌")
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["dotgit_decorator returns decoration for deeply nested .git/ child"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "main", path = "/project/.git/refs/heads/main", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix_hl, "EdaGitIgnoredIcon")
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
end

T["dotgit_decorator returns nil for non-.git entry"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "main.lua", path = "/src/main.lua", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["dotgit_decorator returns nil for .github directory"] = function()
  config.setup()
  local node = Node.create({
    id = 1,
    name = ".github",
    path = "/project/.github",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["dotgit_decorator returns nil for .git file (worktree)"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = ".git", path = "/worktree/.git", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["dotgit_decorator uses custom ignored icon from config"] = function()
  config.setup({ git = { icons = { ignored = "X" } } })
  local node = Node.create({
    id = 1,
    name = ".git",
    path = "/project/.git",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec.suffix, "X")
end

T["dotgit_decorator returns name_hl only when ignored icon is empty"] = function()
  config.setup({ git = { icons = { ignored = "" } } })
  local node = Node.create({
    id = 1,
    name = ".git",
    path = "/project/.git",
    type = "directory",
    open = false,
    children_state = "unloaded",
  })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.dotgit_decorator(node, ctx)
  MiniTest.expect.equality(dec.name_hl, "EdaGitIgnoredName")
  MiniTest.expect.equality(dec.suffix, nil)
  MiniTest.expect.equality(dec.suffix_hl, nil)
end

-- =============================================
-- Symlink decorator tests
-- =============================================

local function make_store_with_root(root_path)
  local Store = require("eda.tree.store")
  local store = Store.new()
  store:set_root(root_path)
  return store
end

T["symlink_decorator returns link_suffix for file symlink"] = function()
  config.setup()
  local store = make_store_with_root("/project")
  local node = Node.create({
    id = 2,
    name = "link.txt",
    path = "/project/link.txt",
    type = "link",
    link_target = "/other/target.txt",
  })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec ~= nil, true)
  MiniTest.expect.equality(dec.link_suffix, "→ ../other/target.txt")
  MiniTest.expect.equality(dec.link_suffix_hl, "EdaSymlinkTarget")
end

T["symlink_decorator returns nil for broken symlink"] = function()
  config.setup()
  local store = make_store_with_root("/project")
  local node = Node.create({ id = 2, name = "broken", path = "/project/broken", type = "link", link_broken = true })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["symlink_decorator returns nil for non-symlink node"] = function()
  config.setup()
  local store = make_store_with_root("/project")
  local node = Node.create({ id = 2, name = "file.txt", path = "/project/file.txt", type = "file" })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["symlink_decorator computes correct relative path for sibling"] = function()
  config.setup()
  local store = make_store_with_root("/home/user/project")
  local node = Node.create({
    id = 2,
    name = "types",
    path = "/home/user/project/types",
    type = "link",
    link_target = "/home/user/shared-types",
  })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec.link_suffix, "→ ../shared-types")
end

T["symlink_decorator computes correct relative path for nested target"] = function()
  config.setup()
  local store = make_store_with_root("/home/user/project")
  local node = Node.create({
    id = 2,
    name = "config",
    path = "/home/user/project/config",
    type = "link",
    link_target = "/home/user/project/src/config",
  })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec.link_suffix, "→ src/config")
end

T["symlink_decorator appends / for directory symlinks"] = function()
  config.setup()
  local store = make_store_with_root("/project")
  local node = Node.create({
    id = 2,
    name = "lib",
    path = "/project/lib",
    type = "directory",
    link_target = "/other/lib",
    children_state = "unloaded",
  })
  local ctx = { store = store, git_status = nil, config = config.get() }
  local dec = decorator.symlink_decorator(node, ctx)
  MiniTest.expect.equality(dec.link_suffix, "→ ../other/lib/")
end

-- =============================================
-- Chain link_suffix merge tests
-- =============================================

T["Chain decorate passes through link_suffix field"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { link_suffix = "→ ../foo", link_suffix_hl = "EdaSymlinkTarget" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "link" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].link_suffix, "→ ../foo")
  MiniTest.expect.equality(result[1].link_suffix_hl, "EdaSymlinkTarget")
end

T["Chain decorate preserves link_suffix alongside suffix"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { link_suffix = "→ ../foo", link_suffix_hl = "EdaSymlinkTarget" }
  end)
  chain:add(function()
    return { suffix = "", suffix_hl = "EdaGitModifiedIcon" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "link" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].link_suffix, "→ ../foo")
  MiniTest.expect.equality(result[1].suffix, "")
end

-- =============================================
-- Mark decorator tests
-- =============================================

T["mark_decorator returns icon/icon_hl/name_hl for marked node"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  node._marked = true
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.mark_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, ctx.config.mark.icon)
  MiniTest.expect.equality(dec.icon_hl, "EdaMarkedNode")
  MiniTest.expect.equality(dec.name_hl, "EdaMarkedNode")
end

T["mark_decorator returns nil for unmarked node"] = function()
  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.mark_decorator(node, ctx)
  MiniTest.expect.equality(dec, nil)
end

T["mark_decorator uses custom icon from config"] = function()
  config.setup({ mark = { icon = "X" } })
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  node._marked = true
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.mark_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "X")
end

T["mark_decorator returns empty icon when mark.icon is empty string"] = function()
  config.setup({ mark = { icon = "" } })
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  node._marked = true
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local dec = decorator.mark_decorator(node, ctx)
  MiniTest.expect.equality(dec.icon, "")
  MiniTest.expect.equality(dec.name_hl, "EdaMarkedNode")
end

T["Chain decorate passes through prefix field (last-write-wins)"] = function()
  local chain = decorator.Chain.new()
  chain:add(function()
    return { prefix = "A" }
  end)
  chain:add(function()
    return { prefix = "B" }
  end)

  config.setup()
  local flat_lines = {
    { node_id = 1, depth = 0, node = Node.create({ id = 1, name = "f", path = "/f", type = "file" }) },
  }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)
  MiniTest.expect.equality(result[1].prefix, "B") -- last wins
end

T["cut + marked node accumulates name_hl and overrides icon"] = function()
  local register = require("eda.register")
  register.set({ "/f" }, "cut")

  local chain = decorator.Chain.new()
  chain:add(decorator.cut_decorator)
  chain:add(decorator.mark_decorator)

  config.setup()
  local node = Node.create({ id = 1, name = "f", path = "/f", type = "file" })
  node._marked = true
  local flat_lines = { { node_id = 1, depth = 0, node = node } }
  local ctx = { store = {}, git_status = nil, config = config.get() }
  local result = chain:decorate(flat_lines, ctx)

  MiniTest.expect.equality(result[1].icon, config.get().mark.icon)
  MiniTest.expect.equality(result[1].icon_hl, "EdaMarkedNode")
  MiniTest.expect.equality(type(result[1].name_hl), "table")
  MiniTest.expect.equality(result[1].name_hl[1], "EdaCut")
  MiniTest.expect.equality(result[1].name_hl[2], "EdaMarkedNode")

  register.clear()
end

return T
