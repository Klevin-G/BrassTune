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

case "$supabase_url" in
    ""|*'$('*) fail "set BRASSTUNE_SUPABASE_URL to the public HTTPS project URL." ;;
    https://?*) ;;
    *) fail "BRASSTUNE_SUPABASE_URL must be an HTTPS URL." ;;
esac

case "$supabase_url" in
    *' '*|*'@'*) fail "BRASSTUNE_SUPABASE_URL must not contain spaces or embedded credentials." ;;
esac

case "$publishable_key" in
    sb_publishable_?*) ;;
    ""|*'$('*) fail "set BRASSTUNE_SUPABASE_PUBLISHABLE_KEY to a public sb_publishable_ key." ;;
    sb_secret_*|*service_role*) fail "secret and service-role keys are forbidden in the app target." ;;
    *) fail "archive builds require a public sb_publishable_ key, never a service key." ;;
esac

echo "BrassTune release auth preflight passed with public configuration present."
