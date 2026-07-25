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
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_secret_test_only \
    /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected a secret-like key to fail." >&2
    exit 1
fi

if CONFIGURATION=Release ACTION=install \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://evil.example \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_0123456789abcdefghij \
    /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected an unexpected API origin to fail." >&2
    exit 1
fi

if CONFIGURATION=Release ACTION=install \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=http://127.0.0.1:8000 \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_0123456789abcdefghij \
    /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected a loopback API origin to fail." >&2
    exit 1
fi

for invalid_url in \
    https://your-project.supabase.co \
    https://abcdefghijklmnopqrst.supabase.co/path \
    https://user@abcdefghijklmnopqrst.supabase.co \
    'https://abcdefghijklmnopqrst.supabase.co?token=value' \
    'https://abcdefghijklmnopqrst.supabase.co#fragment' \
    https://abcdefghijklmnopqrst.supabase.co:443 \
    https://example.invalid/path.supabase.co
do
    if CONFIGURATION=Release ACTION=install \
        BRASSTUNE_ENV=production \
        BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
        BRASSTUNE_SUPABASE_URL="$invalid_url" \
        BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_0123456789abcdefghij \
        /bin/sh "$preflight" >/dev/null 2>&1; then
        echo "Expected malformed or placeholder Supabase URL to fail: $invalid_url" >&2
        exit 1
    fi
done

for invalid_key in \
    sb_publishable_... \
    sb_publishable_short \
    sb_publishable_0123456789abcde! \
    service_role_test_value
do
    if CONFIGURATION=Release ACTION=install \
        BRASSTUNE_ENV=production \
        BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
        BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
        BRASSTUNE_SUPABASE_PUBLISHABLE_KEY="$invalid_key" \
        /bin/sh "$preflight" >/dev/null 2>&1; then
        echo "Expected malformed, placeholder, or secret-like key to fail." >&2
        exit 1
    fi
done

CONFIGURATION=Release ACTION=install \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_0123456789abcdefghij \
    /bin/sh "$preflight"

echo "Release auth preflight tests passed."
