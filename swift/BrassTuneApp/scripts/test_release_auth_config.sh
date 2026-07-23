#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
preflight="$script_dir/verify_release_auth_config.sh"

CONFIGURATION=Debug ACTION=install /bin/sh "$preflight"
CONFIGURATION=Release ACTION=build /bin/sh "$preflight"

if CONFIGURATION=Release ACTION=install /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected a Release archive without public auth configuration to fail." >&2
    exit 1
fi

if CONFIGURATION=Release ACTION=install \
    BRASSTUNE_SUPABASE_URL=https://example.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_secret_test_only \
    /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected a secret-like key to fail." >&2
    exit 1
fi

CONFIGURATION=Release ACTION=install \
    BRASSTUNE_SUPABASE_URL=https://example.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_test_only \
    /bin/sh "$preflight"

echo "Release auth preflight tests passed."
