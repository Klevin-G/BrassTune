#!/bin/sh
set -eu

fail() {
    echo "BrassTune release auth preflight failed: $1" >&2
    exit 1
}

configuration=${CONFIGURATION:-}

# Callback schemes are process identities, not interchangeable provider
# settings. Enforce their exact bundle binding for Release and custom
# Release-equivalent configurations before any guest-only early exit.
case "$configuration" in
    *Release*)
        product_bundle_identifier=${PRODUCT_BUNDLE_IDENTIFIER:-}
        callback_scheme=${BRASSTUNE_AUTH_CALLBACK_SCHEME:-}
        case "$product_bundle_identifier" in
            com.aryasalem.BrassTune)
                expected_callback_scheme=com.brasstune.auth
                ;;
            com.aryasalem.BrassTune.dev|com.brasstune.BrassTuneAppTests.dev|com.brasstune.BrassTuneAppUITests.dev)
                expected_callback_scheme=com.brasstune.auth.dev
                ;;
            *)
                fail "PRODUCT_BUNDLE_IDENTIFIER is not an approved OAuth application identity."
                ;;
        esac
        [ "$callback_scheme" = "$expected_callback_scheme" ] || \
            fail "BRASSTUNE_AUTH_CALLBACK_SCHEME does not match PRODUCT_BUNDLE_IDENTIFIER."
        ;;
esac

# A normal unsigned Release build is allowed to remain guest-only. Archive and
# explicit preflight actions fail closed so an App Store candidate cannot imply
# online account support without its public runtime values.
if [ "$configuration" != "Release" ]; then
    exit 0
fi
if [ "${ACTION:-}" != "install" ] && [ "${BRASSTUNE_REQUIRE_ONLINE_AUTH:-NO}" != "YES" ]; then
    exit 0
fi

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
