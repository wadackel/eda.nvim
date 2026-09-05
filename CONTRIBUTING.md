# Contributing to eda.nvim

## Development Environment

Tool versions are managed by [Nix Flakes](flake.nix). Run commands from the
repository root. Enter the development shell with:

```sh
nix develop
```

[justfile](justfile) is the source for task definitions. Run `just --list` inside
the shell, or `nix develop --command just --list` without entering it.

## Verification Before a Pull Request

Run the complete local check sequence:

```sh
nix develop --command just format-check lint typecheck test-all
```

This checks formatting with StyLua, lints with Selene, checks types with
Lua Language Server, and runs unit and E2E tests. To apply formatting first:

```sh
nix develop --command just format
```

For focused development, use `just test` for unit tests or `just test-e2e` for
E2E tests inside the shell. Both use mini.test; the test bootstrap downloads
mini.nvim into Neovim's data directory when needed. Async unit cases execute
serially so a wait inside one case cannot run other cases nested inside it.

The [CI workflow](.github/workflows/ci.yaml) runs formatting, lint, type checking,
and generated-vimdoc freshness checks. Full unit and E2E suites run on Ubuntu
with Neovim 0.11.0, stable, and nightly, and on macOS with stable Neovim. Test
jobs use temporary dependency/data directories and report the Neovim binary and
version used by the parent and E2E child processes.

To test another installed Neovim locally, use
`just nvim=/absolute/path/to/nvim test-all` inside the development shell. The
same override selects the runtime definitions used by `just typecheck`. CI's
separate typecheck job uses the Neovim and Lua Language Server pinned by Nix.

## Documentation Changes

When changing user-facing configuration, actions, commands, events, highlight
groups, or APIs, update [doc/eda.md](doc/eda.md) and regenerate vimdoc:

```sh
nix develop --command just doc
```

Review and commit both the source and [doc/eda.nvim.txt](doc/eda.nvim.txt). Edit
the Markdown source instead of the generated help file. Keep README examples
and links consistent with the reference. For Nerd Font glyphs in inline code,
use an option name such as `git.icons.added`; panvimdoc cannot render those
glyphs there. Fenced code blocks can contain the glyphs.

## Visual Changes

After changing layouts, icons, highlight groups, Git status display, tree
rendering, or header formatting, regenerate the screenshots:

```sh
nix develop --command just demo-all
```

For iteration on one scenario, use `nix develop --command just demo tree-basic`
with the appropriate [VHS tape](docs/assets/vhs). Visually inspect the generated
images and commit affected files in [docs/assets](docs/assets) together with the
implementation. Command success alone does not establish that a screenshot is
correct.

The image-preview capture `docs/assets/preview-image.png` requires a real
terminal that supports the Kitty graphics protocol. VHS renders through xterm.js
and cannot capture that protocol, so `demo-all` does not produce or refresh this
image. Update it manually when the image-preview appearance changes.

## Performance Changes

Measure render-pipeline, store, decorator, or painter changes before and after
using the same fixture, Neovim version, viewport, and machine:

```sh
nix develop --command nvim --headless -l benchmarks/render.lua /path/to/fixture
```

The fixture path is optional; the script otherwise uses the current directory.
Always run scenario 9 after changing `lua/eda/render/painter.lua` or directory
toggle paths in `lua/eda/init.lua`. It compares incremental and full painting.
The command above runs all nine scenarios.

Follow [the benchmark methodology](benchmarks/README.md) for repeated
measurements and actual toggle, edit-preservation, symlink, or Git workloads.
Run benchmarks sequentially without competing test processes. Record the
workload, revisions, timings, variability, and limitations in the PR; a
headless result is not a measurement of host-terminal display latency.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New feature
- `fix:` — Bug fix
- `refactor:` — Code change that neither fixes a bug nor adds a feature
- `test:` — Adding or updating tests
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks

Indicate breaking changes with `!` after the type, for example
`feat!: remove deprecated API`.

## Pull Requests

1. Create a branch from `main` and keep it focused on one change.
2. Implement the change, add relevant tests, and update documentation or visual
   artifacts as described above.
3. Run the complete local verification sequence and any required benchmarks.
4. Review the full diff, including generated files, then open a PR describing
   the resulting behavior and validation evidence.

PRs are squash-merged. See [AGENTS.md](AGENTS.md) for additional repository
conventions used by coding agents.
