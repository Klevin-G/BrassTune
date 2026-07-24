#!/usr/bin/env bash
set -euo pipefail

install_sqlite_runtime() {
  if [ ! -r /etc/os-release ]; then
    printf 'SQLite runtime provisioning supports Debian/Ubuntu runners only.\n' >&2
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "debian" ] && [ "${ID:-}" != "ubuntu" ]; then
    printf 'SQLite runtime provisioning supports Debian/Ubuntu runners only; found %s.\n' "${ID:-unknown}" >&2
    return 1
  fi

  local -a elevate=()
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1 || ! sudo -n true 2>/dev/null; then
      printf 'SQLite runtime provisioning requires root or passwordless sudo.\n' >&2
      return 1
    fi
    elevate=(sudo -n)
  fi

  "${elevate[@]}" apt-get update
  "${elevate[@]}" apt-get install --yes --no-install-recommends libsqlite3-0
}

if [ "${1:-}" = "--install-sqlite-runtime" ]; then
  install_sqlite_runtime
  exit 0
fi

if [ "$#" -ne 0 ]; then
  printf 'usage: %s [--install-sqlite-runtime]\n' "$0" >&2
  exit 2
fi

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

printf 'Checking BrassTune Linux self-hosted runner tools...\n'
require_cmd git
require_cmd bash
require_cmd curl
require_cmd npm
require_cmd python3.12
require_node_22

python3.12 -m pip --version >/dev/null
python3.12 -m pip_audit --version >/dev/null 2>&1 || {
  printf 'missing: python3.12 -m pip_audit\n' >&2
  missing=1
}
python3.12 -m bandit --version >/dev/null 2>&1 || {
  printf 'missing: python3.12 -m bandit\n' >&2
  missing=1
}

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks version
else
  printf 'warning: gitleaks binary not found; the workflow may still use gitleaks/gitleaks-action if its runtime requirements are available.\n' >&2
fi

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'EOF'

Install missing tools before registering this machine with labels:
self-hosted, brasstune, linux

Suggested package sources:
- Node 22 from NodeSource, nvm, fnm, or the system package manager
- Python 3.12 from the system package manager or pyenv
- pip-audit and Bandit with: python3.12 -m pip install pip-audit bandit
- Playwright dependencies with: npx playwright install --with-deps chromium firefox webkit

EOF
  exit 1
fi

printf 'Linux runner preflight passed.\n'
