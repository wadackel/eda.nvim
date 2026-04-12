#!/usr/bin/env bash
set -euo pipefail

DIR="/tmp/eda-screenshot-project"
rm -rf "$DIR"
mkdir -p "$DIR"

create_base() {
  cd "$DIR"
  git config --global init.defaultBranch main 2>/dev/null || true
  mkdir -p src/components src/utils src/styles tests docs
  echo '{ "name": "my-project" }' > package.json
  echo "# My Project" > README.md
  echo "node_modules/" > .gitignore
  echo 'export function main() {}' > src/index.ts
  cat > src/components/App.tsx << 'CONTENT'
import { Header } from "./Header";
import { Sidebar } from "./Sidebar";

export function App() {
  return (
    <div className="app">
      <Header />
      <Sidebar />
    </div>
  );
}
CONTENT
  echo 'export function Header() {}' > src/components/Header.tsx
  echo 'export function Sidebar() {}' > src/components/Sidebar.tsx
  echo 'export function format() {}' > src/utils/format.ts
  echo 'export function validate() {}' > src/utils/validate.ts
  echo 'body { margin: 0; }' > src/styles/global.css
  echo 'test("app", () => {})' > tests/app.test.ts
  echo '# Guide' > docs/guide.md
  git init -q
  git config user.email "demo@example.com"
  git config user.name "Demo"
  git add -A && git commit -m "init" -q
}

case "${1:-base}" in
  base) create_base ;;
  git)
    create_base
    # staged add
    echo 'export function NewWidget() {}' > src/components/NewWidget.tsx
    git add src/components/NewWidget.tsx
    # staged modify
    echo 'export function main() { console.log("updated") }' > src/index.ts
    git add src/index.ts
    # unstaged modify
    echo 'export function App() { return <main /> }' > src/components/App.tsx
    # untracked
    echo 'export function logger() {}' > src/utils/logger.ts
    # staged delete
    git rm -q src/utils/validate.ts
    ;;
  edit) create_base ;;
esac
