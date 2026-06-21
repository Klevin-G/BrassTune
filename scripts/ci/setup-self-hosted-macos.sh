#!/usr/bin/env bash
set -euo pipefail

missing=0

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    printf 'missing: %s\n' "$name" >&2
    missing=1
  fi
}

require_node_22() {
  require_cmd node
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -p 'process.versions.node.split(".")[0]')"
    if [ "$major" != "22" ]; then
      printf 'expected Node 22, found %s\n' "$(node -v)" >&2
      missing=1
    fi
  fi
}

require_python_312() {
  require_cmd python3.12
}

printf 'Checking BrassTune macOS self-hosted runner tools...\n'
require_cmd git
require_cmd bash
require_cmd curl
require_cmd npm
require_cmd ruby
require_cmd swift
require_cmd xcodebuild
require_cmd xcrun
require_node_22
require_python_312

if command -v python3.12 >/dev/null 2>&1; then
  python3.12 -m pip --version >/dev/null
  python3.12 -m pip_audit --version >/dev/null 2>&1 || {
    printf 'missing: python3.12 -m pip_audit\n' >&2
    missing=1
  }
  python3.12 -m bandit --version >/dev/null 2>&1 || {
    printf 'missing: python3.12 -m bandit\n' >&2
    missing=1
  }
fi

xcodebuild -version
swift --version
xcrun simctl list devices available >/dev/null

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'EOF'

Install missing tools before registering this machine with labels:
self-hosted, brasstune, macos, xcode

Suggested package sources:
- Xcode from Apple
- Node 22 from nodejs.org, nvm, fnm, or Homebrew
- Python 3.12 from python.org, pyenv, or Homebrew
- pip-audit and Bandit with: python3.12 -m pip install pip-audit bandit

EOF
  exit 1
fi

printf 'macOS runner preflight passed.\n'
