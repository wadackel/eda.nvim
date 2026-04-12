# Contributing to eda.nvim

Thank you for your interest in contributing to eda.nvim!

## Development Environment

This project uses [Nix Flakes](https://nixos.wiki/wiki/Flakes) to manage development tools.

```sh
# Enter the development shell (provides all required tools)
nix develop
```

Available tasks are defined in the `justfile`. Run `just --list` to see all commands.

## Running Tests

```sh
# Unit tests
just test

# E2E tests
just test-e2e

# All tests
just test-all
```

## Code Quality

```sh
# Format code with stylua
just format

# Check formatting (CI mode, no writes)
just format-check

# Lint with selene
just lint

# Type check with lua-language-server
just typecheck
```

## Commit Messages

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` — New feature
- `fix:` — Bug fix
- `refactor:` — Code change that neither fixes a bug nor adds a feature
- `test:` — Adding or updating tests
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks

Breaking changes should be indicated with `!` after the type (e.g., `feat!: remove deprecated API`).

## Pull Requests

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Ensure all checks pass (`just format-check && just lint && just test-all`)
4. Submit a pull request

Please keep PRs focused on a single change. If you have multiple unrelated changes, submit separate PRs.
