# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- `nix develop --command just format` — Format with stylua
- `nix develop --command just format-check` — Check formatting (CI mode, no writes)
- `nix develop --command just lint` — Lint with selene
- `nix develop --command just typecheck` — Type check with lua-language-server
- `nix develop --command just test` — Run unit tests with mini.test (`nvim --headless -l tests/minit.lua`)
- `nix develop --command just test-e2e` — Run E2E tests (`nvim --headless -l tests/e2e_minit.lua`)
- `nix develop --command just test-all` — Run all tests (unit + E2E)
- `nvim --headless -l benchmarks/render.lua` — Render pipeline benchmark (uses cwd as target)
- `nvim --headless -l benchmarks/render.lua /path/to/repo` — Benchmark with specific repository
- `nix develop --command just demo-all` — Regenerate all screenshots (requires vhs via `nix develop`)
- `nix develop --command just demo <name>` — Regenerate a single screenshot (e.g., `just demo tree-basic`)

## Development Environment

- Tool versions managed via Nix Flakes (`flake.nix`); task runner is `just` (justfile)
- `nix develop` — Local dev shell (just, stylua, selene, neovim, lua-language-server, git, vhs)
- `nix develop .#ci` — Lightweight CI lint shell (just, stylua, selene only)
- `nix flake update` — Update tool versions (regenerates flake.lock)
- Note: After modifying `flake.nix`, run `git add flake.nix` before `nix flake lock`

## Code Style

- 2-space indentation, 120 character line width (stylua enforced)
- LDoc type annotations (`---@class`, `---@param`, `---@return`, `---@alias`)
- Module pattern: each module returns `M` table, ends with `return M`
- Naming: snake_case for functions/variables, PascalCase for class names in LDoc comments

## Language

- All comments, documentation, commit messages, PR titles/descriptions, and user-facing strings must be written in English
- When invoking skills with language arguments (e.g., `/create-pr ja`), respect this rule — do not use `ja` flag unless the user explicitly requests it

## Testing

- Framework: mini.test (from mini.nvim)
- Test files: `tests/` directory, mirroring `lua/eda/` structure with `test_` prefix
- Test bootstrap: `tests/minit.lua` auto-clones mini.nvim to `~/.local/share/nvim/eda-test-deps/`
- Helper utilities in `tests/helpers.lua` (temp dirs, file creation, wait_for)
- Async tests: use `helpers.wait_for(timeout_ms, predicate_fn)` for `vim.uv` callback completion
- Scanner tests require real filesystem (`helpers.create_temp_dir()`) — `_apply_entries` can populate store synchronously for unit tests but `scan()` needs actual directories

### E2E Tests

- E2E tests use `MiniTest.new_child_neovim()` for process isolation (`--listen pipe` + `vim.uv.sleep()` polling)
- Each test case spawns a fresh child Neovim via `tests/e2e/helpers.lua` — `e2e.spawn()`, `e2e.stop()`, `e2e.exec()`, `e2e.feed()`, `e2e.feed_insert()`, `e2e.wait_until()`, `e2e.setup_eda()`, `e2e.open_eda()`, `e2e.create_git_repo()`, plus `e2e.get_buf_lines()` / `e2e.get_win_count()` / `e2e.get_tab_count()`
- Inner Neovim config: `--clean --headless`, `split_left`, `header=false`, `git.enabled=false`, `icon.provider="none"`
- Headless `--listen` mode limitations: `BufWinEnter`/`BufEnter` do not fire for RPC-initiated commands; `nvim_set_decoration_provider` `on_line` does not fire (no UI redraw). Use `doautocmd` workarounds or verify internal state (`_decoration_cache`) instead
- `wait_until()` wraps multiline predicates in `(function() ... end)()` — single expressions use `return (expr)`, block statements use the function wrapper
- `e2e.feed()` uses `nvim_input` (async, no `v:errmsg` check) to match eda's expected key processing behavior
- `require("eda").open()` on an already-open explorer calls `window:focus()` and returns early — it does NOT re-open with a new config. E2E tests that need to switch `window.kind` / `header` / other config mid-test must either call `require("eda").close()` first or spawn a fresh child via `e2e.spawn()`

## Git Conventions

- Conventional Commits: `feat:`, `fix:`, `chore:`, `refactor:`, `test:`, `docs:`
- Merge strategy: squash merge only (merge commits are not allowed)

## Documentation

- `doc/eda.md` — vimdoc source (panvimdoc generates `doc/eda.nvim.txt`)
- `nix develop --command just doc` — Regenerate vimdoc
- When changing user-facing features (config options, actions, commands, events, highlight groups, API), update `doc/eda.md` accordingly and run `nix develop --command just doc` to regenerate `doc/eda.nvim.txt`
- panvimdoc cannot render Nerd Font (PUA) characters in inline code — use text references (e.g., `git.icons.added`) instead of embedding glyphs directly. Code blocks (fenced) are unaffected

## Screenshots

- `nix develop --command just demo-all` — Regenerate all screenshots (PNG/GIF) in `docs/assets/vhs/`
- `nix develop --command just demo <name>` — Regenerate a single screenshot (e.g., `just demo tree-basic`)
- When changing user-facing visuals (window layout, icons, highlight groups, git status display, tree rendering, header format), regenerate screenshots after implementation by running `nix develop --command just demo-all`
- Tape files (`docs/assets/vhs/*.tape`) define VHS recording scenarios; `docs/assets/vhs/setup.sh` creates fixture directories; `docs/assets/vhs/init.lua` is the minimal Neovim config for recordings
- After regeneration, visually inspect the generated images (Read tool can display PNG/GIF) and commit them together with the code changes
- VHS `Output` supports GIF/MP4/WebM only; for PNG use `Screenshot <file>.png` (works without `Output`)
- eda.nvim opens with directories collapsed by default; tapes use `gE` (expand_all) after startup to show full tree
- init.lua sets `swapfile=false` to prevent swap conflicts when running multiple tapes sequentially

## Architecture Notes

- Pure Lua plugin, no external dependencies beyond Neovim built-in APIs
- Async filesystem operations via `vim.uv`
- Neovim is single-threaded: `vim.schedule` callbacks execute sequentially, so parallel `vim.uv` operations with `vim.schedule` completions do not race on store mutations
- macOS-specific Unicode NFC normalization in `util.lua` for filesystem compatibility
- Extmark `right_gravity`: default `true` (shifts with inserted text), `false` (stays at position). For `virt_text_pos="inline"` icons, `right_gravity=false` keeps the icon before typed text, but may not track line-level shifts from editor commands (e.g., `o`). Use `ns_ids` extmarks (right_gravity=true) as the authoritative position source and resync `ns_icon` extmarks via `_resync_on_redraw()` in the decoration provider's `on_win` callback
- Extmark `hl_mode`: default `"replace"` overwrites line-level attributes (CursorLine, Visual). Use `"combine"` for virt_text that should inherit these attributes
- Extmark `invalidate=true`: `nvim_buf_set_lines` that replaces a line marks the extmark as `invalid=true`; when reading extmarks with `details=true`, check `m[4].invalid` to skip invalidated marks. This affects `get_cursor_node()` which falls back to extmark lookup when `vim.bo.modified` is true
- Rendering uses `nvim_set_decoration_provider` for ephemeral highlights (only visible lines are decorated on each redraw)
- Avoid API calls like `nvim_buf_get_lines` inside the decoration provider `on_line` callback (incurs per-line overhead). Pre-compute and cache required data during `paint()`
- `on_win` callback (once per window per redraw) can safely call `nvim_buf_get_extmarks`, `nvim_buf_clear_namespace`, and `nvim_buf_set_extmark`. Use position comparison to skip unnecessary rebuilds (fast path)
- Float window titles render on top of the float border: padding with spaces replaces the border horizontal character and breaks the visual frame. To right-align content in a float title (e.g., a status indicator), fill the gap with the border's horizontal char (`─` for rounded/single, `═` for double) rather than spaces. `title_pos` (center/right) additionally shifts the entire chunk array, so right-edge padding layouts only work with `title_pos = "left"` — fall back to adjacent placement for other positions
- `nvim_win_set_config({title = {{text, hl_group}, ...}})` accepts chunk arrays for multi-highlight float titles (Neovim 0.9+). `nvim_win_get_config(winid).title` round-trips the same chunk form; plain string titles are normalized to a single-element chunk `{{text}}`
- Mark invariant: nodes carry `_marked = true|nil` (2-state). Action target resolution across mark-aware operations (delete/cut/copy/duplicate/paste) follows `Visual > marks > cursor` priority (single source of truth in `action/builtin.lua`)
- Mark highlight pattern: `EdaMarked` (base, `Special` link) → `EdaMarkedIcon` / `EdaMarkedName` (both linked to `EdaMarked`). On setup and `ColorScheme` events, `bg` / `ctermbg` are stripped from resolved `EdaMarked` to avoid clobbering `CursorLine` / `Visual`
- `paint_incremental()` (`render/painter.lua`): directory expand/collapse uses a differential paint strategy driven by `_incremental_hint` (node ID of the toggled dir) set in `init.lua`. Only the affected line range is re-decorated, avoiding a full-buffer repaint

## Benchmarking

- Script: `benchmarks/render.lua` — run via `nvim --headless -l benchmarks/render.lua [target_dir]`
- 9 scenarios (1-6: baseline render pipeline — root-only / all-expanded / post-toggle / re-render / window+render / window+re-render; 7: single-toggle profiled breakdown; 8: edit-preserve capture profiled; 9: `paint_incremental` vs full paint)
- Run before and after performance-related changes (render pipeline, store, decorator, painter) and compare results
- Headless mode does not measure `nvim_set_decoration_provider` visible-line optimization; Scenarios 5-6 (with window) partially compensate
- Scenario 9 is the regression gate for `paint_incremental` (used on directory toggle to avoid full-buffer repaint). Always run Scenario 9 after touching `painter.lua` or `init.lua` toggle paths
- For large-scale benchmarking: `git clone --depth=1 https://github.com/neovim/neovim /tmp/neovim-bench` → run benchmark → `rm -rf /tmp/neovim-bench`
