local Node = require("eda.tree.node")

---@class eda.Scanner
---@field store eda.Store
---@field config table
---@field _scanning table<integer, boolean>
---@field _active_fds integer
---@field _max_concurrent_fds integer
---@field _node_gen table<integer, integer>
---@field _pending_scans { node_id: integer, callback: fun(err?: string), gen: integer }[]
---@field _waiters table<integer, fun(err?: string)[]>
local Scanner = {}
Scanner.__index = Scanner

---Create a new scanner bound to a store.
---@param store eda.Store
---@param config? table
---@return eda.Scanner
function Scanner.new(store, config)
  return setmetatable({
    store = store,
    config = config or {},
    _scanning = {},
    _node_gen = {},
    _active_fds = 0,
    _max_concurrent_fds = 32,
    _pending_scans = {},
    _waiters = {},
  }, Scanner)
end

---Resolve file type from lstat result.
---@param stat table uv_fs_stat result
---@return "file"|"directory"|"link"
local function resolve_type(stat)
  if stat.type == "directory" then
    return "directory"
  elseif stat.type == "link" then
    return "link"
  else
    return "file"
  end
end

---Drain pending scans while under the fd limit.
---@private
function Scanner:_drain_pending()
  while #self._pending_scans > 0 and self._active_fds < self._max_concurrent_fds do
    local entry = table.remove(self._pending_scans, 1)
    self._active_fds = self._active_fds + 1
    self:_do_scan_io(entry.node_id, entry.callback, entry.gen)
  end
end

---Release one fd slot and drain pending scans.
---@private
function Scanner:_release_fd()
  self._active_fds = self._active_fds - 1
  self:_drain_pending()
end

---Scan a single directory node asynchronously.
---@param node_id integer
---@param callback fun(err?: string)
function Scanner:scan(node_id, callback)
  local node = self.store:get(node_id)
  if not node or not Node.is_dir(node) then
    if callback then
      callback("not a directory")
    end
    return
  end

  if self._scanning[node_id] then
    -- Coalesce: queue callback so it fires when the in-flight scan settles.
    if callback then
      self._waiters[node_id] = self._waiters[node_id] or {}
      table.insert(self._waiters[node_id], callback)
    end
    return
  end

  self._scanning[node_id] = true
  -- Per-node generation: track which scan is active for this specific node
  local gen = (self._node_gen[node_id] or 0) + 1
  self._node_gen[node_id] = gen
  node.children_state = "loading"

  if self._active_fds < self._max_concurrent_fds then
    self._active_fds = self._active_fds + 1
    self:_do_scan_io(node_id, callback, gen)
  else
    table.insert(self._pending_scans, { node_id = node_id, callback = callback, gen = gen })
  end
end

---Settle a scan: invoke the original callback, then drain any coalesced waiters.
---Waiters always fire even on abandoned (gen-mismatch) scans so callers cannot wait forever.
---@private
---@param node_id integer
---@param callback fun(err?: string)?
function Scanner:_settle(node_id, callback)
  if callback then
    callback()
  end
  local waiters = self._waiters[node_id]
  if waiters then
    self._waiters[node_id] = nil
    for _, w in ipairs(waiters) do
      w()
    end
  end
end

---Perform the actual I/O for a directory scan.
---@private
---@param node_id integer
---@param callback fun(err?: string)
---@param gen integer
function Scanner:_do_scan_io(node_id, callback, gen)
  local node = self.store:get(node_id)
  if not node then
    callback("node not found")
    return
  end

  vim.uv.fs_opendir(node.path, function(err, dir)
    if err then
      vim.schedule(function()
        self:_release_fd()
        self._scanning[node_id] = nil
        if self._node_gen[node_id] ~= gen then
          self:_settle(node_id, callback)
          return
        end
        node.children_state = "loaded"
        self.store:remove_children(node_id)
        -- Create error child node
        self.store:add({
          name = err,
          path = node.path .. "/__error__",
          type = "file",
          parent_id = node_id,
          error = "permission_denied",
        })
        self:_settle(node_id, callback)
      end)
      return
    end

    local entries = {}

    local function read_next()
      vim.uv.fs_readdir(dir, function(read_err, ents)
        if read_err or not ents then
          vim.uv.fs_closedir(dir, function()
            vim.schedule(function()
              self:_release_fd()
              self._scanning[node_id] = nil
              if self._node_gen[node_id] ~= gen then
                self:_settle(node_id, callback)
                return
              end
              self:_apply_entries(node_id, entries)
              self:_settle(node_id, callback)
            end)
          end)
          return
        end

        for _, ent in ipairs(ents) do
          table.insert(entries, ent)
        end
        read_next()
      end)
    end

    read_next()
  end, 64)
end

---Apply scanned entries to the store.
---@param node_id integer
---@param entries table[]
function Scanner:_apply_entries(node_id, entries)
  local node = self.store:get(node_id)
  if not node then
    return
  end

  self.store:remove_children(node_id)

  local follow_symlinks = self.config.follow_symlinks ~= false
  local show_hidden = self.config.show_hidden ~= false

  local ignore_patterns = self.config.ignore_patterns or {}
  if type(ignore_patterns) == "function" then
    local root = self.store:get(self.store.root_id)
    ignore_patterns = ignore_patterns(root and root.path or "") or {}
  end

  for _, ent in ipairs(entries) do
    -- Filter hidden files (dotfiles) unless show_hidden is enabled
    if not show_hidden and ent.name:sub(1, 1) == "." then
      goto continue_entry
    end

    -- Filter by ignore patterns
    for _, pattern in ipairs(ignore_patterns) do
      if ent.name:match(pattern) then
        goto continue_entry
      end
    end

    local child_path = node.path .. "/" .. ent.name
    local child_type = resolve_type(ent)

    local fields = {
      name = ent.name,
      path = child_path,
      type = child_type,
      parent_id = node_id,
    }

    if child_type == "link" then
      local target = vim.uv.fs_realpath(child_path)
      if target then
        fields.link_target = target
        fields.link_broken = false
        if follow_symlinks then
          local target_stat = vim.uv.fs_stat(target)
          if target_stat and target_stat.type == "directory" then
            fields.type = "directory"
          end
        end
      else
        fields.link_target = nil
        fields.link_broken = true
      end
    end

    self.store:add(fields)
    ::continue_entry::
  end

  node.children_state = "loaded"
end

---Scan ancestor directories from root to target path.
---@param target_path string Absolute path to the target file/directory
---@param callback fun()
function Scanner:scan_ancestors(target_path, callback)
  local root = self.store:get(self.store.root_id)
  if not root then
    if callback then
      callback()
    end
    return
  end

  -- Decompose target_path into segments relative to root
  local root_path = root.path
  local rel = target_path:sub(#root_path + 2) -- strip root_path + "/"
  if rel == "" then
    -- Target is root itself
    self:scan(self.store.root_id, function()
      if callback then
        callback()
      end
    end)
    return
  end

  local segments = {}
  for seg in rel:gmatch("[^/]+") do
    table.insert(segments, seg)
  end

  -- Scan root first, then each ancestor directory
  local current_id = self.store.root_id
  local idx = 0

  local function scan_next()
    self:scan(current_id, function()
      idx = idx + 1
      if idx > #segments then
        if callback then
          callback()
        end
        return
      end

      -- Find child matching next segment
      local seg = segments[idx]
      local current_node = self.store:get(current_id)
      if current_node and current_node.children_ids then
        for _, child_id in ipairs(current_node.children_ids) do
          local child = self.store:get(child_id)
          if child and child.name == seg and Node.is_dir(child) then
            child.open = true
            current_id = child_id
            scan_next()
            return
          end
        end
      end

      -- Segment not found, stop
      if callback then
        callback()
      end
    end)
  end

  scan_next()
end

---Recursively scan open directories up to a depth limit.
---@param node_id integer
---@param max_depth integer
---@param callback fun()
function Scanner:scan_recursive(node_id, max_depth, callback)
  if max_depth <= 0 then
    if callback then
      callback()
    end
    return
  end

  self:scan(node_id, function()
    local node = self.store:get(node_id)
    if not node or not node.children_ids then
      if callback then
        callback()
      end
      return
    end

    -- Collect directory children
    local dirs = {}
    for _, child_id in ipairs(node.children_ids) do
      local child = self.store:get(child_id)
      if child and Node.is_dir(child) then
        table.insert(dirs, child_id)
      end
    end

    if #dirs == 0 then
      if callback then
        callback()
      end
      return
    end

    local batch_size = 32
    local function scan_batch(start_idx)
      local end_idx = math.min(start_idx + batch_size - 1, #dirs)
      local batch_completed = 0
      for i = start_idx, end_idx do
        self:scan_recursive(dirs[i], max_depth - 1, function()
          batch_completed = batch_completed + 1
          if batch_completed == (end_idx - start_idx + 1) then
            if end_idx < #dirs then
              scan_batch(end_idx + 1)
            elseif callback then
              callback()
            end
          end
        end)
      end
    end
    scan_batch(1)
  end)
end

---Iteratively scan all open but unloaded directories.
---Applies open_dirs map between iterations to mark newly-scanned nodes.
---Terminates when no open+unloaded directories remain.
---@param open_dirs table<string, boolean> path→true map of dirs that should be open
---@param callback fun()
function Scanner:scan_open_unloaded(open_dirs, callback)
  -- Apply open states using path index (O(|open_dirs|) instead of O(|all_nodes|))
  for path in pairs(open_dirs) do
    local node = self.store:get_by_path(path)
    if node and Node.is_dir(node) then
      node.open = true
    end
  end

  -- Collect open + unloaded directories using path index
  local dirs_to_scan = {}
  for path in pairs(open_dirs) do
    local node = self.store:get_by_path(path)
    if node and Node.is_dir(node) and node.open and node.children_state == "unloaded" then
      dirs_to_scan[#dirs_to_scan + 1] = node.id
    end
  end

  if #dirs_to_scan == 0 then
    if callback then
      callback()
    end
    return
  end

  local remaining = #dirs_to_scan
  for _, nid in ipairs(dirs_to_scan) do
    self:scan(nid, function()
      remaining = remaining - 1
      if remaining == 0 then
        vim.schedule(function()
          self:scan_open_unloaded(open_dirs, callback)
        end)
      end
    end)
  end
end

---@param root_id integer
---@param callback fun()
function Scanner:rescan_preserving_state(root_id, callback)
  local open_by_path = {}
  local marked_by_path = {}
  for _, node in pairs(self.store.nodes) do
    if node.id ~= root_id then
      if Node.is_dir(node) and node.open then
        open_by_path[node.path] = true
      end
      if node._marked then
        marked_by_path[node.path] = true
      end
    end
  end
  self:scan(root_id, function()
    self:scan_open_unloaded(open_by_path, function()
      -- Restore _marked flags for nodes that still exist after rescan.
      if next(marked_by_path) ~= nil then
        for _, node in pairs(self.store.nodes) do
          if marked_by_path[node.path] then
            node._marked = true
          end
        end
      end
      callback()
    end)
  end)
end

return Scanner
