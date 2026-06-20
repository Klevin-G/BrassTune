# App Privacy Draft

Updated: 2026-06-20 UTC.

This draft is for owner/legal review. It is not a final App Store privacy nutrition-label answer.

## Data Categories

| Category | Current Use | Linked To User | Shared With |
|---|---|---:|---|
| Email/account profile | Auth, account recovery, ensemble identity | Yes when signed in | Supabase/Auth provider |
| Practice sessions and pitch metrics | Analytics, progress, recommendations | Yes when signed in; local for guest | Backend/hosting provider |
| Audio recordings | Relisten/playback when recorded | Yes when signed in; local for guest | Supabase Storage if configured |
| Score PDFs/images | Practice-with-score source material | Local by default | Not uploaded by current web score practice |
| Camera/microphone input | Capture score pages and pitch/audio | Processed on device/browser during use | Not uploaded unless a future explicit path is added |
| Logs | Operations/debugging | May include account/session IDs | Vercel/Render/Supabase provider logs |

## Privacy Commitments To Preserve

- No Supabase service-role or secret key in browser/native bundles.
- No source score pages in export reports by default.
- No logging raw recordings, OAuth payloads, score contents, filenames with sensitive data, passwords, or tokens.
- Account deletion must remove app rows and attempt provider identity/storage cleanup.
- Guest data stays on device unless the user exports or signs in through a future migration path.

## Required Owner Review

- Legal controller identity.
- Public privacy policy URL.
- Terms URL/text.
- Support contact.
- Age rating and school/minor-data position.
- App Store privacy questionnaire answers.
- Third-party SDK privacy manifest/signature review.
