local Node = require("eda.tree.node")

local M = {}

---@class eda.Decoration
---@field prefix string?
---@field prefix_hl string?
---@field icon string?
---@field icon_hl string?
---@field name_hl (string|string[])?
---@field suffix string?
---@field suffix_hl string?
---@field link_suffix string?
---@field link_suffix_hl string?

---@class eda.DecoratorContext
---@field store eda.Store
---@field git_status table<string, string>?
---@field config eda.Config
---@field _git_symbol_map table?

---@alias eda.DecoratorFn fun(node: eda.TreeNode, ctx: eda.DecoratorContext): eda.Decoration?

---@class eda.DecoratorChain
---@field decorators eda.DecoratorFn[]
local Chain = {}
Chain.__index = Chain

---Create a new decorator chain.
---@param decorators? eda.DecoratorFn[]
---@return eda.DecoratorChain
function Chain.new(decorators)
  return setmetatable({
    decorators = decorators or {},
  }, Chain)
end

---Add a decorator to the chain.
---@param fn eda.DecoratorFn
function Chain:add(fn)
  table.insert(self.decorators, fn)
end

---Apply all decorators to a list of flat lines.
---Sequential application: name_hl uses append (stacked hl_group arrays),
---all other fields use last-write-wins.
---@param flat_lines eda.FlatLine[]
---@param ctx eda.DecoratorContext
---@return eda.Decoration[]
function Chain:decorate(flat_lines, ctx)
  local result = {}
  for i, fl in ipairs(flat_lines) do
    local merged = {}
    local name_hl_list
    for _, dec_fn in ipairs(self.decorators) do
      local dec = dec_fn(fl.node, ctx)
      if dec then
        if dec.prefix ~= nil then
          merged.prefix = dec.prefix
        end
        if dec.prefix_hl ~= nil then
          merged.prefix_hl = dec.prefix_hl
        end
        if dec.icon ~= nil then
          merged.icon = dec.icon
        end
        if dec.icon_hl ~= nil then
          merged.icon_hl = dec.icon_hl
        end
        if dec.name_hl ~= nil then
          if not name_hl_list then
            name_hl_list = { dec.name_hl }
          else
            name_hl_list[#name_hl_list + 1] = dec.name_hl
          end
        end
        if dec.suffix ~= nil then
          merged.suffix = dec.suffix
        end
        if dec.suffix_hl ~= nil then
          merged.suffix_hl = dec.suffix_hl
        end
        if dec.link_suffix ~= nil then
          merged.link_suffix = dec.link_suffix
        end
        if dec.link_suffix_hl ~= nil then
          merged.link_suffix_hl = dec.link_suffix_hl
        end
      end
    end
    if name_hl_list then
      merged.name_hl = #name_hl_list == 1 and name_hl_list[1] or name_hl_list
    end
    result[i] = merged
  end
  return result
end

---Compute a relative path from `from_dir` to `to_path`.
---Both arguments must be absolute paths.
---@param from_dir string
---@param to_path string
---@return string
local function relative_path(from_dir, to_path)
  local function split(p)
    local parts = {}
    for seg in p:gmatch("[^/]+") do
      parts[#parts + 1] = seg
    end
    return parts
  end
  local from_parts = split(from_dir)
  local to_parts = split(to_path)
  local common = 0
  for i = 1, math.min(#from_parts, #to_parts) do
    if from_parts[i] ~= to_parts[i] then
      break
    end
    common = i
  end
  local result = {}
  for _ = common + 1, #from_parts do
    result[#result + 1] = ".."
  end
  for i = common + 1, #to_parts do
    result[#result + 1] = to_parts[i]
  end
  if #result == 0 then
    return "."
  end
  return table.concat(result, "/")
end

-- Built-in decorators

-- Cached icon provider resolution (resolved once per provider config value)
---@type { provider: string, type: string, get_fn: function? }?
local _icon_cache = nil

---Resolve and cache the icon provider function.
---@param provider string
---@return { provider: string, type: string, get_fn: function? }?
local function resolve_icon_provider(provider)
  if _icon_cache and _icon_cache.provider == provider then
    if _icon_cache.get_fn then
      return _icon_cache
    end
    -- Negative cache hit: no provider available for this config value
    return nil
  end

  local mod_name, mod_type
  if provider == "mini_icons" then
    mod_name, mod_type = "mini.icons", "mini"
  elseif provider == "nvim_web_devicons" then
    mod_name, mod_type = "nvim-web-devicons", "devicons"
  end

  if mod_name then
    local ok, mod = pcall(require, mod_name)
    if ok then
      local fn = mod_type == "mini" and function(name)
        return mod.get("file", name)
      end or function(name)
        return mod.get_icon(name, nil, { default = true })
      end
      _icon_cache = { provider = provider, type = mod_type, get_fn = fn }
      return _icon_cache
    end
    vim.notify(
      "eda: icon provider '" .. provider .. "' not found. Install it or set icon.provider = 'none'.",
      vim.log.levels.WARN
    )
  end

  -- Cache negative result to avoid repeated pcall on every node
  _icon_cache = { provider = provider, type = "none", get_fn = nil }
  return nil
end

---Icon decorator: resolves in order custom hook → directory glyph → provider lookup.
---@param node eda.TreeNode
---@param ctx eda.DecoratorContext
---@return eda.Decoration?
function M.icon_decorator(node, ctx)
  local cfg_icon = ctx.config.icon or {}

  if cfg_icon.custom then
    local r1, r2 = cfg_icon.custom(node.name, node)
    if r1 ~= nil then
      return { icon = r1, icon_hl = r2 }
    end
  end

  if Node.is_dir(node) then
    local dir = cfg_icon.directory or {}
    local is_empty = node.children_ids and #node.children_ids == 0 and node.children_state == "loaded"
    local icon
    if node.open and is_empty then
      icon = dir.empty_open
    elseif node.open then
      icon = dir.expanded
    elseif is_empty then
      icon = dir.empty
    else
      icon = dir.collapsed
    end
    return { icon = icon or "", icon_hl = "EdaDirectoryIcon" }
  end

  local cached = resolve_icon_provider(cfg_icon.provider or "mini_icons")
  if cached then
    local ic, hl = cached.get_fn(node.name)
    if ic then
      return { icon = ic, icon_hl = hl }
    end
  end

  return nil
end

---Git decorator: shows git status as suffix.
---@param node eda.TreeNode
---@param ctx eda.DecoratorContext
---@return eda.Decoration?
function M.git_decorator(node, ctx)
  if not ctx.git_status then
    return nil
  end

  local status = ctx.git_status[node.path]
  if not status then
    if require("eda.git").is_gitignored(ctx.git_status, node.path) then
      status = "!"
    else
      return nil
    end
  end

  if not ctx._git_symbol_map then
    local icons = ctx.config.git.icons or {}
    ctx._git_symbol_map = {
      ["?"] = { symbol = icons.untracked or "?", suffix_hl = "EdaGitUntrackedIcon", name_hl = "EdaGitUntrackedName" },
      ["A"] = { symbol = icons.added or "+", suffix_hl = "EdaGitAddedIcon", name_hl = "EdaGitAddedName" },
      ["M"] = { symbol = icons.modified or "~", suffix_hl = "EdaGitModifiedIcon", name_hl = "EdaGitModifiedName" },
      ["D"] = { symbol = icons.deleted or "", suffix_hl = "EdaGitDeletedIcon", name_hl = "EdaGitDeletedName" },
      ["R"] = { symbol = icons.renamed or "→", suffix_hl = "EdaGitRenamedIcon", name_hl = "EdaGitRenamedName" },
      ["C"] = { symbol = icons.staged or "=", suffix_hl = "EdaGitStagedIcon", name_hl = "EdaGitStagedName" },
      ["U"] = { symbol = icons.conflict or "!", suffix_hl = "EdaGitConflictIcon", name_hl = "EdaGitConflictName" },
      ["!"] = { symbol = icons.ignored or "#", suffix_hl = "EdaGitIgnoredIcon", name_hl = "EdaGitIgnoredName" },
    }
  end

  local info = ctx._git_symbol_map[status]
  if not info then
    return nil
  end

  if info.symbol == "" then
    return nil
  end

  -- Directories only get suffix highlighting, not name
  -- Exception: ignored directories should be visually distinct since ignored status
  -- is not propagated from children — it applies directly to the directory itself
  if Node.is_dir(node) then
    if status == "!" then
      return { suffix = info.symbol, suffix_hl = info.suffix_hl, name_hl = info.name_hl }
    end
    return { suffix = info.symbol, suffix_hl = info.suffix_hl }
  end

  return { suffix = info.symbol, suffix_hl = info.suffix_hl, name_hl = info.name_hl }
end

---Check if a node is inside the .git directory.
---@param node eda.TreeNode
---@return boolean
local function is_dotgit(node)
  if node.name == ".git" and Node.is_dir(node) then
    return true
  end
  return node.path:find("/.git/", 1, true) ~= nil
end

---.git decorator: styles .git directory and its children like git-ignored entries.
---@param node eda.TreeNode
---@param ctx eda.DecoratorContext
---@return eda.Decoration?
function M.dotgit_decorator(node, ctx)
  if not is_dotgit(node) then
    return nil
  end

  local icon = ctx.config.git.icons.ignored
  if icon == "" then
    return { name_hl = "EdaGitIgnoredName" }
  end

  return { suffix = icon, suffix_hl = "EdaGitIgnoredIcon", name_hl = "EdaGitIgnoredName" }
end

---Symlink decorator: shows link target as suffix.
---@param node eda.TreeNode
---@param ctx eda.DecoratorContext
---@return eda.Decoration?
function M.symlink_decorator(node, ctx)
  if not node.link_target then
    return nil
  end
  local root_node = ctx.store:get(ctx.store.root_id)
  if not root_node then
    return nil
  end
  local rel = relative_path(root_node.path, node.link_target)
  if Node.is_dir(node) then
    rel = rel .. "/"
  end
  return { link_suffix = "→ " .. rel, link_suffix_hl = "EdaSymlinkTarget" }
end

---Cut decorator: dims nodes that are in the cut register.
---@param node eda.TreeNode
---@param _ctx eda.DecoratorContext
---@return eda.Decoration?
function M.cut_decorator(node, _ctx)
  local register = require("eda.register")
  if register.is_cut(node.path) then
    return { name_hl = "EdaCut", icon_hl = "EdaCut" }
  end
  return nil
end

-- U+F0132 (nf-md-checkbox_marked). Built via string.char to avoid PUA-character dropping.
local MARK_ICON = string.char(0xf3, 0xb0, 0x84, 0xb2)

---Mark decorator: shows a prefix marker icon on marked nodes.
---@param node eda.TreeNode
---@param ctx eda.DecoratorContext
---@return eda.Decoration?
function M.mark_decorator(node, ctx)
  if not node._marked then
    return nil
  end
  local icon = ctx.config.mark and ctx.config.mark.icon or MARK_ICON
  return { icon = icon, icon_hl = "EdaMarkedNode", name_hl = "EdaMarkedNode" }
end

M.Chain = Chain

return M
