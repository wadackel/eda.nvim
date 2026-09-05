# Architecture

eda.nvim represents a directory tree in an editable Neovim buffer. This document
explains the data and execution boundaries; the [user reference](../doc/eda.md)
contains configuration, actions, APIs, and event payloads.

## Store, buffer identity, and snapshots

[Store](../lua/eda/tree/store.lua) holds nodes by ID and indexes paths for lookup.
IDs increase within a store. Reconciliation retains an existing node, its loaded
descendants, and caches when its name, path, type, link metadata, and error state
are unchanged. Replaced entries receive new IDs. A root change creates a new
store; node IDs are not persistent filesystem identities.

Directories start unloaded and materialize children when scanned. Collapsing a
directory changes its visibility and retains loaded children. Memory use grows
with the loaded tree, cached metadata, and rendered rows; a small viewport does
not bound the size of the store.

[Painter](../lua/eda/render/painter.lua) places node IDs in the `ns_ids` extmark
namespace, separate from buffer text and icon extmarks. The
[parser](../lua/eda/buffer/parser.lua) uses valid ID marks to associate edited
rows with existing nodes. Invalidated marks are excluded from that lookup;
unmarked text can represent a new entry.

A render snapshot maps painted node IDs to their paths and buffer rows. These
are all tree rows in the buffer, including rows outside the viewport. Collapsed
or filtered-out descendants are absent. The [diff](../lua/eda/tree/diff.lua)
compares parsed edits against this snapshot, so a hidden descendant's absence
from the buffer does not become a deletion. The snapshot is an editing baseline,
not an atomic filesystem snapshot or a general conflict detector.

## Scanning and refresh

[Scanner](../lua/eda/tree/scanner.lua) enumerates directories with asynchronous
`vim.uv` calls in batches of 64 entries. Up to 32 scans are active per scanner.
Retained symlinks use the [metadata resolver](../lua/eda/tree/metadata.lua), with
up to 32 asynchronous realpath/optional-stat chains active across that scanner's
directories. Ordinary files require no per-entry metadata request. Scan slots
remain occupied until metadata completion and child reconciliation.

Filtering, preparing entries, reconciling nodes, sorting, and render preparation
still execute synchronously on Neovim's main loop. Symlink metadata completes
before children are committed, so callback order does not determine display
order. Disposal stops queued work; submitted requests drain without committing
stale results. The scanner checks node, path, root, and generation ownership.
These asynchronous scan operations do not imply that every filesystem access
elsewhere in the plugin is asynchronous.

[Refresh](../lua/eda/refresh.lua) watches the root and visible expanded
directories. Known directory events are coalesced into scoped refreshes; unknown
events require a broader refresh. A refresh waits while the buffer is modified,
a write is in progress, or the active scanner is busy. It scans into a candidate
store and adopts results only if buffer changedtick, render/store generations,
root ownership, and write state still permit it. Otherwise it requests another
refresh. Adoption reconciles the existing store instead of replacing IDs beneath
pending edits. Unchanged structural results do not require a structural repaint;
Git completion can still trigger a render.

## Rendering and cursor placement

The render pipeline flattens the expanded, filtered tree, runs decorators, and
paints text and cached display metadata. Its work is broader than the terminal's
visible rows.

For a compatible clean-buffer directory toggle, `paint_incremental` validates
that surviving node order is unchanged and inserts or removes the affected
contiguous range. It updates decorations and icon extmarks for the toggled and
inserted nodes, plus the first surviving icon at an insertion boundary. Existing
extmarks track the shift of other rows.

The toggle still flattens and decorates the displayed tree. Incremental painting
also builds whole-row ID lookup tables, row mappings, line lengths, and a fresh
snapshot. It therefore does not make the entire toggle proportional only to the
inserted or removed range. An incompatible hint, edited baseline, or other
render path uses full painting, which rebuilds the node-ID and icon namespaces.
Expanding or collapsing while preserving edits also captures and replays buffer
changes; that path has additional parsing and painting costs.

A decoration provider applies ephemeral highlights to viewport rows during
redraw, using metadata prepared during painting. Its `on_win` callback skips
extmark resynchronization when changedtick is unchanged. User edits can require
examining all ID/icon positions and rebuilding icon placement; visible-row
highlighting does not remove that work.

Startup scans a requested target's ancestor chain before the initial render.
Restored open directories and requested descendants can require subsequent
scans. [Buffer.restore_cursor](../lua/eda/buffer/init.lua) prefers an explicit
`focus_node_id` over a saved `target_node_id` and finds its row in the flattened
list. The render path clears both targets after each paint. A target must be loaded
and included in the current tree to be placed; there is no constant-time or
instant-placement guarantee for large or slow filesystems.

[Benchmark methodology and recorded measurements](../benchmarks/README.md)
distinguish full pipeline work, incremental painting, actual toggle actions,
and redraw. Headless measurements do not establish host-terminal display
latency. Performance changes need measurements of the path being changed.

## Writes and mutation events

A buffer write parses edits, computes operations from the painted baseline,
validates their structure and destinations, and executes them sequentially.
Directory toggles that preserve edits capture the current buffer state before
repainting and replay it against the resulting tree. Refresh/write guards keep
asynchronous results from silently replacing that editing baseline.

[Mutation execution](../lua/eda/mutation.lua) surrounds a nonempty operation
batch with one `EdaMutationPre` and one `EdaMutationPost`. The post event reports
the completed prefix and any failed operation; it is delivered even if the
originating explorer has closed. Integrations must use `results.completed` to
report successful changes. The [LSP recipe](../doc/eda.md#lsp-rename-notifications)
implements post-rename notifications, not pre-rename workspace edits.

Validation and exclusive creation reduce destructive collisions, but the batch
is not a transaction. An error stops later operations; completed operations are
not rolled back, and a failed recursive operation can leave partial output.
External processes can change paths between checks and filesystem operations.
Recovery reconciles completed changes while retaining unapplied edits or action
targets for retry; it does not provide isolation from external filesystem edits.

## Integration boundaries

- **Actions:** [the registry](../lua/eda/action/init.lua) maps names to functions.
  Built-in and custom actions receive the same `ActionContext`. `ga` opens the
  action picker; mappings and programmatic dispatch use registered names.
- **Appearance:** decorators prepare icons, names, Git indicators, and marks.
  Named highlight groups cover the tree, filesystem state, operations, dialogs,
  and previews. The layouts are `float`, `split_left`, `split_right`, and `replace`.
- **Git:** [the request coordinator](../lua/eda/git.lua) allows one active status
  process and one queued round per repository. Requests before launch are
  batched; requests after launch need a fresh round. Successful cached data stays
  usable during refresh, while invalidation prevents old results from replacing
  it. Raw NUL-delimited output preserves pathname boundaries.
- **Image preview:** [the Kitty client](../lua/eda/image/kitty.lua) owns image
  transmission and placement. Cursor movement and placement are emitted in one
  write, with border and tmux offsets, to keep placement coordinates together.
  Its interface follows `vim.ui.img` where possible; source cropping is an extra
  operation that a future replacement would need to handle.
- **Directory entry points:** `hijack_netrw` routes directory edits into the
  explorer. Root selection and target-file navigation are separate: a target
  does not automatically imply changing the configured root.
