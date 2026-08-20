# Google and Apple Sign-in

Updated: 2026-08-19. Do not put credentials in Git, logs, screenshots, or this document.

## Current state

| Provider | Web | iOS | Linked Supabase state |
|---|---|---|---|
| Google | Enabled Supabase OAuth with PKCE and a Google-branded button; production sign-in, restore, and sign-out completed with an ordinary test identity | Enabled native PKCE flow; an attended physical `.dev` lifecycle completed callback, cold restore, sign-out, and signed-out relaunch | Enabled on the linked production provider configuration. The successful dated lifecycles still require exact-candidate repetition and deletion/expiry coverage. |
| Apple | Enabled with the web Services ID first and a rotating provider secret stored outside Git; a fresh Safari flow completed callback, restore, sign-out, and signed-out reload | Enabled native ID-token flow; production and `.dev` App IDs, entitlement, provisioning, and native button are present; an attended physical lifecycle completed callback, restore, sign-out, and signed-out relaunch | Enabled with `com.aryasalem.BrassTune.web` first, followed by the production and `.dev` native App IDs. The saved secret remains provider-side/environment-only. |

Native provider discovery presents both Apple and Google when live provider
settings are available. Guest practice and first-party email/password remain
available. The hosted web app presents Apple and Google. The dated successful
provider lifecycles do not replace exact-candidate repetition, token-expiry,
account-deletion, cross-user denial, or Storage cleanup acceptance.

## Credential and CLI boundary

The existing Supabase CLI session can read the linked project and verify migrations without another Supabase login or database password. It cannot create Apple Developer resources or Apple-issued credentials. Never share an Apple password with Supabase, Codex, or this repository.

`supabase config push` applies the complete local Auth configuration; it is not
a provider-only mutation and has no dry-run flag. The checked-in Apple client-ID
order matches the live web/native topology, but a push must fail closed unless
`SUPABASE_AUTH_APPLE_SECRET` is supplied from an authorized secret store. Never
replace that environment reference with a literal secret or run config push
merely to verify live state.

## Google verification checklist

1. Keep the Google provider enabled in Supabase and preserve the Supabase callback URL in Google Cloud.
2. Preserve the reconciled eight-entry Supabase redirect allowlist: production and owner-restricted preview callback/reset URLs, localhost callback/reset URLs, and escaped production/development native callbacks.
3. On an exact candidate, test success, cancel, callback error, session refresh, restoration, and sign-out with disposable identities on web and signed iOS hardware.
4. Confirm no provider token or secret appears in browser logs, native logs, or analytics.

## Apple verification checklist

1. Preserve the web Services ID first, followed by both native App IDs, and preserve the production entitlement/provisioning value.
2. Rotate the Apple client-secret JWT before expiry and inject it only through the authorized provider/environment secret store.
3. On each signed exact candidate, repeat native and web success/cancel/callback-error/restoration/refresh/sign-out/deletion checks with disposable identities.
4. Never commit the `.p8` key, generated secret, provider token, or signed URL.

## References

- [Supabase Google auth](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Apple auth](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Apple Sign in with Apple](https://developer.apple.com/documentation/authenticationservices/)
- [Google OAuth for installed apps](https://developers.google.com/identity/protocols/oauth2/native-app)
