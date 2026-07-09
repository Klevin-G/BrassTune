# Sign in with Google / Apple — setup

The code is fully wired on both platforms:
- **Web** — `AuthContext.signInWithGoogle/signInWithApple` call `supabase.auth.signInWithOAuth(...)`,
  gated by `VITE_AUTH_GOOGLE_ENABLED` / `VITE_AUTH_APPLE_ENABLED`; "Continue with Google/Apple"
  buttons render when enabled. Redirect target: `<origin>/auth/callback`.
- **Native (iOS)** — `SettingsViews.swift` uses `SignInWithAppleButton`; the
  `com.apple.developer.applesignin` entitlement is now in the target.

What remains is provider configuration, which needs OAuth credentials that only the
account owner can create (they are tied to your Google/Apple accounts).

## Google (fastest — no paid account needed)

1. Google Cloud Console → **APIs & Services → Credentials → Create credentials → OAuth client ID**.
   - Application type: **Web application**.
   - **Authorized redirect URI:** `https://yznziwewxrlwnwiynlvl.supabase.co/auth/v1/callback`
   - Copy the **Client ID** and **Client secret**.
2. Supabase → **Authentication → Providers → Google** → enable → paste Client ID + Secret → Save.
3. Supabase → **Authentication → URL Configuration**:
   - Site URL: `https://brass-tune.vercel.app`
   - Redirect URLs: add `https://brass-tune.vercel.app/auth/callback`,
     `https://*.vercel.app/auth/callback`, `http://localhost:5173/auth/callback`.
4. Enable the button: set `VITE_AUTH_GOOGLE_ENABLED=true` in Vercel (Production + Preview) and redeploy.

> Give me the Google **Client ID + Secret** and I'll do steps 2–4 for you (or paste them into
> the dashboard yourself — it's ~4 clicks).

## Apple (requires paid Apple Developer Program)

Web:
1. Apple Developer → **Identifiers → Services IDs → +** (e.g. `com.brasstune.web`) →
   enable **Sign in with Apple** → configure: primary App ID = the app's bundle id,
   Return URL = `https://yznziwewxrlwnwiynlvl.supabase.co/auth/v1/callback`.
2. Apple Developer → **Keys → +** → enable Sign in with Apple → download the `.p8`,
   note the **Key ID** and **Team ID**.
3. Supabase → **Authentication → Providers → Apple** → enable → Services ID as client id →
   provide the key (Supabase generates the client secret JWT) → Save.
4. Set `VITE_AUTH_APPLE_ENABLED=true` in Vercel and redeploy.

Native (iOS): the entitlement is in place. In your Apple Developer account, enable the
**Sign in with Apple** capability on the app's App ID (automatic signing + `-allowProvisioningUpdates`
in the archive script will register it). The button then exchanges the Apple identity token with Supabase.

## Notes
- Leave `VITE_AUTH_*_ENABLED` **off** until the matching Supabase provider is configured,
  otherwise the button appears but the OAuth attempt errors.
- The current email/password auth is fully working and unaffected by any of the above.
