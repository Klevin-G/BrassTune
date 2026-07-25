# Google and Apple Sign-in

Updated: 2026-07-24. Do not put credentials in Git, logs, screenshots, or this document.

## Current state

| Provider | Web | iOS | Linked Supabase state |
|---|---|---|---|
| Google | Supabase OAuth with PKCE and a Google-branded button | Code remains implemented for later dual-provider enablement; it is not presented in this Apple-deferred native build. | Enabled on the linked provider configuration; native presentation is intentionally deferred. |
| Apple | Supabase OAuth button and unavailable state | Deferred: the entitlement and native control are absent until Apple Developer credentials and provider configuration are verified. | Disabled; Apple Developer credentials and Supabase provider configuration are still required. |

Native unavailable provider controls are hidden, not disabled. Because Apple is deferred, native Google OAuth is also not presented in this build; guest practice and first-party email/password remain available. This keeps the native release path within App Review Guideline 4.8 until both third-party-provider parity and live verification exist. The Google implementation remains in source for later dual-provider enablement.

## Credential and CLI boundary

The existing Supabase CLI session can read the linked project and verify migrations without another Supabase login or database password. It cannot create Apple Developer resources or Apple-issued credentials. Never share an Apple password with Supabase, Codex, or this repository.

`supabase config push` applies the complete local Auth configuration; it is not a provider-only mutation and has no dry-run flag. Do not use it for Apple until the entire TOML is reviewed and the Google and Apple secret environment variables are securely available. After an authorized Apple owner creates the Team ID, Services ID, Key ID, `.p8` key, and client-secret JWT, prefer the targeted Supabase Management API Auth-config update or a fully reviewed CLI config push.

## Google verification checklist

1. Keep the Google provider enabled in Supabase and preserve the Supabase callback URL in Google Cloud.
2. Keep production and owner-restricted preview callback URLs in Supabase Auth.
3. After exact-SHA deploy, test success, cancel, callback error, session refresh, and sign-out with a disposable account on web and iOS.
4. Confirm no provider token or secret appears in browser logs, native logs, or analytics.

## Apple enablement checklist

1. In Apple Developer, create/configure the Services ID and return URL for the Supabase callback, enable Sign in with Apple for the native App ID, and generate the required key/team metadata.
2. Configure and enable the Apple provider in Supabase; do not commit the `.p8` key or generated secret.
3. Update the production Apple flag only after the live authorize flow succeeds; deploy the exact merged SHA.
4. Test success, cancel, first-use email behavior, callback error, session refresh, sign-out, and account deletion with disposable identities on web and signed iOS hardware.

## References

- [Supabase Google auth](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Apple auth](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Apple Sign in with Apple](https://developer.apple.com/documentation/authenticationservices/)
- [Google OAuth for installed apps](https://developers.google.com/identity/protocols/oauth2/native-app)
