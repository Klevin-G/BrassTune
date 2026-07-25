# App Privacy Draft

Updated: 2026-07-24 UTC.

This draft is for owner/legal review. It is not a final App Store privacy nutrition-label answer.

## Data Categories

| Category | Current Use | Linked To User | Shared With |
|---|---|---:|---|
| Email/account profile | Auth, account recovery, ensemble identity | Yes when signed in | Supabase/Auth provider |
| Practice sessions and pitch metrics | Analytics, progress, recommendations | Yes when signed in; browser-local for guest | Authenticated backend/Supabase path for signed-in web practice; not shared with a class |
| Web microphone audio | Optional practice listen-back | Guest: browser-local until deleted, browser data is cleared, or exported. Signed in: uploaded automatically when the user stops a recorded take, through the authenticated backend/Supabase path | Not shared with class directors or class-report surfaces. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation; export/share is user-initiated |
| Native microphone audio | Live pitch analysis and optional practice listen-back | Retained only in the app's local storage when the user records a take, until the user deletes it or clears local data. It is not uploaded automatically | Not shared unless the user explicitly exports or shares it |
| Account-linked user content | Practice metadata, imported-score metadata, and optional reflections used for account functionality | Yes when signed in | Backend/hosting provider only for authenticated cloud paths; never exposed to class reporting as raw reflection text or private session detail |
| Score PDFs/images | Practice-with-score source material | Local by default | Not uploaded by current web score practice |
| Camera/microphone input | Capture score pages and pitch/audio | Processed on device/browser during use | Not uploaded unless a future explicit path is added |
| Logs | Operations/debugging | May include account/session IDs | Vercel/Render/Supabase provider logs |

## Privacy Commitments To Preserve

- No Supabase service-role or secret key in browser/native bundles.
- No source score pages in export reports by default.
- No logging raw recordings, OAuth payloads, score contents, filenames with sensitive data, passwords, or tokens.
- Account deletion must remove app rows and attempt provider identity/storage cleanup.
- Guest web data, including guest recordings, stays in that browser until the user deletes it, clears browser data, or exports it. Native recordings stay app-local until deletion, clearing local data, or an explicit export/share.
- Signed-in web recordings upload automatically at Stop; the published privacy page must continue to disclose this distinction.
- Class directors and class-report surfaces receive aggregate cloud practice totals only. They do not receive recordings, reflection text, or private session detail. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation.
- The iOS privacy manifest is limited to linked email address, user ID, and account-linked user content for app functionality; it does not list raw microphone audio as collected.
- `ITSAppUsesNonExemptEncryption=false` is appropriate only while native networking uses Apple-provided HTTPS/TLS and platform security services without non-exempt custom cryptography.

## Required Owner Review

- Legal controller identity.
- Confirm the published privacy, terms, and support pages at `https://brasstune.vercel.app/privacy`, `/terms`, and `/support` remain accurate for the signed build and the deployed web recording behavior; the support page is the native support-contact source.
- Age rating and school/minor-data position.
- App Store privacy questionnaire answers.
- Third-party SDK privacy manifest/signature review.
