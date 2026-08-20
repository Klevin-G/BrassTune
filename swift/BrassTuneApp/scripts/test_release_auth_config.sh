#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
preflight="$script_dir/verify_release_auth_config.sh"

release_preflight() {
    env \
        CONFIGURATION=Release \
        ACTION=install \
        PRODUCT_BUNDLE_IDENTIFIER=com.aryasalem.BrassTune \
        BRASSTUNE_AUTH_CALLBACK_SCHEME=com.brasstune.auth \
        "$@" \
        /bin/sh "$preflight"
}

CONFIGURATION=Debug ACTION=install /bin/sh "$preflight"
release_preflight ACTION=build

if mismatch_output=$(env \
    CONFIGURATION=Release \
    ACTION=build \
    PRODUCT_BUNDLE_IDENTIFIER=com.aryasalem.BrassTune.dev \
    BRASSTUNE_AUTH_CALLBACK_SCHEME=com.brasstune.auth \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sensitive_test_marker \
    /bin/sh "$preflight" 2>&1); then
    echo "Expected a Release .dev bundle with the production callback to fail." >&2
    exit 1
fi
case "$mismatch_output" in
    *sensitive_test_marker*)
        echo "Release identity failure output disclosed an auth configuration value." >&2
        exit 1
        ;;
esac

env \
    CONFIGURATION=Release \
    ACTION=build \
    PRODUCT_BUNDLE_IDENTIFIER=com.aryasalem.BrassTune.dev \
    BRASSTUNE_AUTH_CALLBACK_SCHEME=com.brasstune.auth.dev \
    /bin/sh "$preflight"

if env \
    CONFIGURATION=ReleaseCandidate \
    ACTION=build \
    PRODUCT_BUNDLE_IDENTIFIER=com.aryasalem.BrassTune.dev \
    BRASSTUNE_AUTH_CALLBACK_SCHEME=com.brasstune.auth \
    /bin/sh "$preflight" >/dev/null 2>&1; then
    echo "Expected a Release-equivalent identity mismatch to fail." >&2
    exit 1
fi

if release_preflight >/dev/null 2>&1; then
    echo "Expected a Release archive without public auth configuration to fail." >&2
    exit 1
fi

if release_preflight \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_"secret"_test_only \
    >/dev/null 2>&1; then
    echo "Expected a secret-like key to fail." >&2
    exit 1
fi

if release_preflight \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://evil.example \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_"publishable"_0123456789abcdefghij \
    >/dev/null 2>&1; then
    echo "Expected an unexpected API origin to fail." >&2
    exit 1
fi

if release_preflight \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=http://127.0.0.1:8000 \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_"publishable"_0123456789abcdefghij \
    >/dev/null 2>&1; then
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
    if release_preflight \
        BRASSTUNE_ENV=production \
        BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
        BRASSTUNE_SUPABASE_URL="$invalid_url" \
        BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_"publishable"_0123456789abcdefghij \
        >/dev/null 2>&1; then
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
    if release_preflight \
        BRASSTUNE_ENV=production \
        BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
        BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
        BRASSTUNE_SUPABASE_PUBLISHABLE_KEY="$invalid_key" \
        >/dev/null 2>&1; then
        echo "Expected malformed, placeholder, or secret-like key to fail." >&2
        exit 1
    fi
done

release_preflight \
    BRASSTUNE_ENV=production \
    BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
    BRASSTUNE_SUPABASE_URL=https://abcdefghijklmnopqrst.supabase.co \
    BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_"publishable"_0123456789abcdefghij

echo "Release auth preflight tests passed."
