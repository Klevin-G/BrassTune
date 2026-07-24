#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 0 ]; then
  printf 'usage: %s\n' "$0" >&2
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

printf 'Checking BrassTune Linux self-hosted runner tools...\n'
require_cmd git
require_cmd bash
require_cmd curl
require_cmd pg_config

if ! ldconfig -p 2>/dev/null | grep -q 'libsqlite3\.so\.0'; then
  printf 'missing: pre-baked libsqlite3.so.0 runtime\n' >&2
  missing=1
fi

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'EOF'

Install missing tools before registering this machine with labels:
self-hosted, brasstune, linux, docker

Suggested package sources:
- Pre-bake libsqlite3, PostgreSQL, and Playwright system libraries into the runner image.
- Let pinned actions/setup-node and actions/setup-python select job toolchains.
- Keep package audits and browser binaries installed inside each trusted job.

EOF
  exit 1
fi

printf 'Linux runner preflight passed.\n'
