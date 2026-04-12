# Override: just nvim=/path/to/nvim test
nvim := "nvim"

# Format with stylua
format:
    stylua lua/ plugin/ tests/

# Check formatting (CI mode)
format-check:
    stylua --check lua/ plugin/ tests/

# Lint with selene
lint:
    selene lua/ plugin/

# Type check with lua-language-server
typecheck:
    #!/usr/bin/env bash
    set -euo pipefail
    export VIMRUNTIME=$(nvim --headless +"echo \$VIMRUNTIME" +q 2>&1 | tail -1)
    lua-language-server --check lua/ --configpath <(jq --arg vr "$VIMRUNTIME/lua" '.workspace.library += [$vr]' .luarc.json)

# Run unit tests with mini.test
test:
    {{ nvim }} --headless -l tests/minit.lua

# Run E2E tests
test-e2e:
    {{ nvim }} --headless -l tests/e2e_minit.lua

# Run all tests (unit + E2E)
test-all: test test-e2e

# Generate a specific demo (requires vhs)
demo name:
    vhs "docs/assets/vhs/{{ name }}.tape"

# Generate all demos
demo-all:
    rm -rf /tmp/eda-screenshot-deps
    for tape in docs/assets/vhs/*.tape; do vhs "$tape"; done

# Generate vimdoc from doc/eda.md
doc:
    panvimdoc \
      --project-name eda.nvim \
      --input-file doc/eda.md \
      --vim-version "Neovim >= 0.11" \
      --toc true \
      --description "Tree-view file explorer with buffer-native editing"
