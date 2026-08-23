# App Privacy Draft
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23 UTC.

This draft is for owner/legal review. It is not a final App Store privacy nutrition-label answer.

Project attribution: Kelvin Guo, Arya Salem. This attribution does not identify
the legal controller; that remains subject to owner/legal review.

## Data Categories

| Category | Current Use | Linked To User | Shared With |
|---|---|---:|---|
| Email/account profile | Auth, account recovery, account/profile completion, and ensemble identity | Yes when signed in | Supabase/Auth provider and authenticated backend |
| Profile display name | Account profile and in-app identity | Yes | Authenticated backend only; not used for advertising or tracking |
| Optional profile photo | Account profile selected by the person | Yes | Private, backend-proxied Supabase Storage only; not public, not shared with classes, and not used for advertising or tracking |
| Practice sessions and pitch metrics | Analytics, progress, recommendations | Yes when signed in; browser-local for guest | Authenticated backend/Supabase path for signed-in web practice; not shared with a class |
| Camera input | User-initiated score-page capture/import | Processed on device/browser during use | Not uploaded by the current score-capture path |
| Passive microphone input and pitch frames | Live tuner and microphone-assisted practice feedback | Processed locally during the active listening feature; raw passive frames are not uploaded | Not shared as raw audio; derived practice metrics follow the account/guest session boundary |
| Explicit recorded take audio — web | Optional practice listen-back | Guest: browser-local until deleted, browser data is cleared, or exported. Signed in: uploaded through the authenticated backend/Supabase path when the person stops an explicit recorded take | Not shared with class directors or class-report surfaces. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation; export/share is user-initiated |
| Explicit recorded take audio — native | Optional practice listen-back | Retained in app-local storage when the person records a take, until deletion or local-data clearing; it is not uploaded automatically | Leaves the device only through an explicit export/share action |
| Account-linked user content | Practice metadata, imported-score metadata, and optional reflections used for account functionality | Yes when signed in | Backend/hosting provider only for authenticated cloud paths; never exposed to class reporting as raw reflection text or private session detail |
| Score PDFs/images | Practice-with-score source material | Local by default | Not uploaded by current web score practice |
| Logs | Operations/debugging | May include account/session IDs | Vercel/Render/Supabase provider logs |

## Privacy Commitments To Preserve

- No Supabase service-role or secret key in browser/native bundles.
- No source score pages in export reports by default.
- No logging raw recordings, OAuth payloads, score contents, filenames with sensitive data, passwords, or tokens.
- Account deletion must remove app rows and attempt provider identity/storage cleanup.
- Guest web data, including guest recordings, stays in that browser until the user deletes it, clears browser data, or exports it. Native recordings stay app-local until deletion, clearing local data, or an explicit export/share.
- Signed-in web recordings upload automatically at Stop; the published privacy page must continue to disclose this distinction.
- A profile photo is optional. Local source is designed to send it only after
  the person saves the profile, normalize it, retain the active object in a
  private profile-avatar bucket, and serve it only through the authenticated
  account endpoint. Replacement/removal and account deletion are designed to
  queue cleanup. Backend lifecycle validation and deployment evidence remain
  pending.
- The local backend export contract, pending lifecycle validation and deployment,
  includes the current avatar binary only when present at the fixed safe path
  `profile/avatar.jpg`, plus bounded metadata at `profile/avatar.json`.
  `account.json` includes current profile metadata, including avatar
  availability/update time. The export must never expose a storage object key or
  source path; when no avatar is present, it must omit both avatar entries.
- Class directors and class-report surfaces receive aggregate cloud practice totals only. They do not receive recordings, reflection text, or private session detail. A limited set of authorized BrassTune service administrators may access account/session/audio data only for security, support, abuse investigation, or service operation.
- The checked-in iOS privacy manifest declares linked email address, user ID,
  Name, Photos or Videos, and other user content for app functionality, with
  tracking disabled. Confirm that the final signed binary retains this manifest;
  raw microphone audio remains local-only and is not collected by the native
  app.
- `ITSAppUsesNonExemptEncryption=false` is appropriate only while native networking uses Apple-provided HTTPS/TLS and platform security services without non-exempt custom cryptography.

## App Store App Privacy guidance for the profile feature

This is prepared questionnaire guidance, not evidence that App Store Connect has
been changed. For the profile implementation that is local at this writing,
declare the following if the final candidate still sends the data to the
backend:

| App Store data type | Collected | Linked to user | Tracking | Purpose |
|---|---:|---:|---:|---|
| Contact Info — Name (display name) | Yes | Yes | No | App Functionality |
| User Content — Photos or Videos (optional profile photo) | Yes | Yes | No | App Functionality |

Apple describes **Name** as contact information and **Photos or Videos** as
user content, and requires disclosure for a user-uploaded media type. Apple
also defines tracking as linking app data with third-party data for targeted
advertising or advertising measurement, or sharing it with a data broker.
BrassTune's planned profile path does neither. Source: [Apple App Privacy
Details](https://developer.apple.com/app-store/app-privacy-details/).

## Required Owner Review

- Legal controller identity.
- Confirm the published privacy, terms, and support pages at `https://brasstune.vercel.app/privacy`, `/terms`, and `/support` remain accurate for the signed build and the deployed web recording behavior; the support page is the native support-contact source.
- Age rating and school/minor-data position.
- App Store privacy questionnaire answers, including the linked/nontracking
  **Name** and **Photos or Videos** entries above, both with **App
  Functionality** as the purpose.
- Confirmation that the App Store Connect questionnaire was saved for the final
  candidate; this documentation change does not update App Store Connect.
- Third-party SDK privacy manifest/signature review.
