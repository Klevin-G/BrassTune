# Native public runtime configuration

BrassTune's native account client needs an immutable production API origin and two public Supabase values:

- `BRASSTUNE_ENV=production`.
- `BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com`; archives reject every other origin.

- `BRASSTUNE_SUPABASE_URL`: the project's public HTTPS URL.
- `BRASSTUNE_SUPABASE_PUBLISHABLE_KEY`: an `sb_publishable_...` client key.

These values are designed to be embedded in the app's generated `Info.plist`.
They are not service credentials. Never provide an `sb_secret_` key, a
`service_role` JWT, a database password, or any hidden environment value to the
app target.

## Release injection

Set the two user-defined build settings on the `BrassTuneApp` Release target in
Xcode or pass them to the release build/archive job. Example values below are
placeholders only:

```sh
xcodebuild \
  -project BrassTuneApp.xcodeproj \
  -scheme BrassTuneApp \
  -configuration Release \
  BRASSTUNE_ENV=production \
  BRASSTUNE_API_BASE_URL=https://brasstune-u8qj.onrender.com \
  BRASSTUNE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_REPLACE_ME \
  build
```

The target copies the build settings into `BRASSTUNE_SUPABASE_URL` and
`BRASSTUNE_SUPABASE_PUBLISHABLE_KEY` in the generated app `Info.plist`. Process
environment values still override the plist for local tests, but packaged apps
do not depend on a shell environment.

An ordinary Release build with blank settings remains explicitly guest-only.
The target's archive preflight runs for `ACTION=install` and fails when either
public value is absent, unresolved, non-HTTPS, or secret-like. This prevents an
App Store candidate from silently shipping account controls without usable
public configuration.

Run the standalone preflight regression checks with:

```sh
/bin/sh scripts/test_release_auth_config.sh
```

Passing this preflight is not an archive, signing, provider, or App Store
readiness claim. Those still require authorized release infrastructure and live
provider verification.
