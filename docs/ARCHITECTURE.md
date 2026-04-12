# Architecture

This document records the architecture, design philosophy, and trade-offs behind eda.nvim. It serves as a reference for developers and AI agents to understand the reasoning behind key design choices.

## Design Principles

### Buffer-Native File Operations

Edit the explorer buffer like any Vim buffer — rename by changing text, delete by removing lines, create by adding new lines — then `:w` to apply all changes to the real filesystem.

This extends oil.nvim's buffer-editing paradigm to a full tree view. Each line carries a concealed node ID for reliable tracking. Invalidated extmarks (e.g. from external formatters mangling lines) are skipped during parsing, and the computed operations are then validated for structural errors — missing rename targets, duplicate destinations — before execution.

### Tree View with Hierarchy

Directories are displayed as a collapsible tree, not a flat per-directory listing. This is the core differentiation from oil.nvim — eda.nvim combines hierarchical tree navigation with buffer-native editing.

Collapsed (hidden) nodes are excluded from the diff on `:w`, preventing accidental deletion of files that aren't visible in the buffer.

### Progressive Async Rendering

All filesystem scanning is fully asynchronous via `vim.uv`. The target file's ancestor chain is scanned first, so the relevant portion of the tree appears immediately. Remaining directories load progressively in the background.

Directory expand/collapse — the hot path for re-render — is applied incrementally: only the affected line range is replaced via `nvim_buf_set_lines`. Other changes fall back to a full repaint.

### Stable Startup Experience

A `target_node_id` tracks which node the cursor should land on. As async scanning progresses and new nodes become paintable, the cursor is placed on the target as soon as its line is rendered — no jitter, no reset.

This directly solves the cursor instability seen in fyler.nvim, where async scan completion would reset the cursor position. The target is held until the user manually moves the cursor.

### Flexible Appearance

60+ highlight groups organized into six categories — structure (`EdaNormal`, `EdaBorder`, `EdaIndentMarker`), filesystem (`EdaDirectoryName`, `EdaFileName`, `EdaSymlink`, `EdaBrokenSymlink`), git status (`EdaGitModified`, `EdaGitAdded`, ...), operation confirmation (`EdaOpCreate`, `EdaOpDelete`, ...), confirm UI, and help / full-name popup.

A decorator chain (flatten → decorate → paint) allows icon providers, git status indicators, and custom decorators to be composed, replaced, or extended independently.

### Extensible Action System

All operations (navigation, file manipulation, UI toggles) are registered in a named action registry and dispatched by string name. This replaces hardcoded keybinding functions with a discoverable, composable system.

Every action receives a unified `ActionContext` containing the `store`, `buffer`, `window`, `scanner`, `config`, and `explorer` instance. Cursor-position and marked-node state are reached through the `buffer` field, making custom actions first-class citizens with the same capabilities as built-in ones.

### Multiple Window Layouts

Four layout kinds serve different workflows:

- **float** — Centered overlay for quick file picking
- **split_left** / **split_right** — Persistent sidebar for ongoing navigation
- **replace** — Inline buffer replacement (oil.nvim style)

### Git Integration

Asynchronous git status detection via `vim.system()`, surfaced through the decorator chain as file-level status icons. Runs as a standard decorator, maintaining rendering consistency with other display elements.

### netrw Replacement

With `hijack_netrw` enabled, `:edit <directory>` opens eda.nvim instead of netrw, providing a seamless default file browsing experience.

### Event Hooks

User autocommands (`EdaTreeOpen`, `EdaTreeClose`, `EdaMutationPre`, `EdaMutationPost`) enable integration with external plugins such as nvim-lsp-file-operations for automatic LSP workspace updates on file rename/move.

## Architecture Decisions

| Decision | Rationale |
| --- | --- |
| Flat store (`id → node`) | No path-segment splitting needed. `path_index` (`path → id`) provides O(1) lookup. Simpler than a Trie + EntryManager dual structure |
| Two-phase render | Ancestor chain scanned first → cursor placed immediately → remaining dirs load async. Eliminates startup cursor jitter |
| Action registry | String-name registration + dispatch. Easy to extend, easy to discover (`:Eda actions` / which-key integration) |
| Decorator chain | Rendering split into flatten → decorate → paint. Each decorator is independently replaceable. Icon, git, and custom decorators compose via last-wins override |
| Smart root resolution | Default: `cwd`. With `update_focused_file.update_root`, root follows the active buffer's project (via `vim.fs.root()` markers). Solves the "file outside cwd" problem |
| Lazy child materialization | Unexpanded directories hold no children in memory (`children_state = "unloaded"`). Keeps memory usage bounded for 100k+ file repositories |
| Render snapshot for diff | Buffer `:w` compares against the last painted snapshot, not the full store. Only visible (painted) nodes participate in diff — collapsed subtrees are safe |

## Comparison with Existing Plugins

| Aspect | fyler.nvim | oil.nvim | eda.nvim |
| --- | --- | --- | --- |
| Paradigm | Tree + buffer editing | Flat (single dir) + buffer editing | Tree + buffer editing |
| Tree storage | Trie + EntryManager (dual structure) | None (per-directory) | Flat store + path_index |
| Initial render | Fully async (cursor bug source) | Synchronous | Async, ancestor-first scan |
| Action system | Hardcoded functions | Action string indirection | Named registry + dispatch |
| Highlight groups | ~23 (color-oriented) | Few | 60+ (structure / FS / git / operations / confirm / help) |
| Root resolution | Always cwd | Buffer's directory | cwd + update_root (nvim-tree style) |
| Rendering pipeline | Component tree (Row/Column/Text) | Direct buffer write | flatten → decorate → paint |
| Extensibility | mappings with self | Adapter abstraction | ActionContext + Decorator chain + User autocmds |
| Hierarchy display | Yes | No (no nesting) | Yes |
