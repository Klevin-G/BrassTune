#!/bin/sh
set -eu

# A normal unsigned Release build is allowed to remain guest-only. Archive and
# explicit preflight actions fail closed so an App Store candidate cannot imply
# online account support without its public runtime values.
if [ "${CONFIGURATION:-}" != "Release" ]; then
    exit 0
fi
if [ "${ACTION:-}" != "install" ] && [ "${BRASSTUNE_REQUIRE_ONLINE_AUTH:-NO}" != "YES" ]; then
    exit 0
fi

fail() {
    echo "BrassTune release auth preflight failed: $1" >&2
    exit 1
}

supabase_url=${BRASSTUNE_SUPABASE_URL:-}
publishable_key=${BRASSTUNE_SUPABASE_PUBLISHABLE_KEY:-}
api_base_url=${BRASSTUNE_API_BASE_URL:-}
app_environment=${BRASSTUNE_ENV:-}

[ "$app_environment" = "production" ] || fail "BRASSTUNE_ENV must be production for an archive."
[ "$api_base_url" = "https://brasstune-u8qj.onrender.com" ] || fail "BRASSTUNE_API_BASE_URL must be the approved immutable production origin."

case "$supabase_url" in
    ""|*'$('*) fail "set BRASSTUNE_SUPABASE_URL to the public HTTPS project URL." ;;
    *your-project*|*YOUR_PROJECT*|*example*|*invalid*|*'...'*) fail "BRASSTUNE_SUPABASE_URL must not be a placeholder." ;;
esac
if ! printf '%s\n' "$supabase_url" | grep -Eq '^https://[a-z0-9]{20}\.supabase\.co$'; then
    fail "BRASSTUNE_SUPABASE_URL must be exactly https://<20-character-project-ref>.supabase.co with no path, credentials, port, query, or fragment."
fi

case "$publishable_key" in
    ""|*'$('*) fail "set BRASSTUNE_SUPABASE_PUBLISHABLE_KEY to a public sb_publishable_ key." ;;
    *'...'*) fail "BRASSTUNE_SUPABASE_PUBLISHABLE_KEY must not be a placeholder." ;;
    sb_secret_*|*service_role*) fail "secret and service-role keys are forbidden in the app target." ;;
esac
if ! printf '%s\n' "$publishable_key" | grep -Eq '^sb_publishable_[A-Za-z0-9_-]{20,}$'; then
    fail "archive builds require a complete public sb_publishable_ key, never a placeholder or service key."
fi

echo "BrassTune release auth preflight passed with public configuration present."
