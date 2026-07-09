# Closed Beta Handoff

Status: web/backend closed-beta production path deployed and smoke-passed in guest/auth-disabled mode; external provider/App Store/device gates remain.

## Tester URLs

- Production web URL: `https://brass-tune.vercel.app`
- Backend API: `https://brasstune-u8qj.onrender.com`
- Backend health: `https://brasstune-u8qj.onrender.com/api/health`
- WebSocket endpoint: `wss://brasstune-u8qj.onrender.com/ws/pitch`

The old branch preview may require Vercel Authentication and should not be the primary tester URL now that PR #2 is merged.

## Supported Platforms For This Beta

- Web: current desktop Chromium, Firefox, WebKit/Safari-like browsers, and mobile browser viewports covered by local Playwright/device simulation.
- Native iOS: simulator smoke only. Do not treat simulator results as physical microphone, TestFlight, or App Store evidence.
- Backend: hosted Render health, CORS, browser-origin WebSocket app response, query-token rejection, and bad-origin rejection smoke passed.

## What To Try

Guest testers should:

1. Open the app.
2. Complete onboarding.
3. Use the demo tuner.
4. Record and stop a practice take.
5. Open session review.
6. Try playback where available.
7. Export session/account data surfaces.
8. Open analytics, progress, and coach.
9. Open settings, Privacy, Terms, and Support.
10. Check mobile layout.
11. Deny microphone permission and confirm the recovery message is understandable.

Teacher/director testers should:

1. Open the ensemble dashboard.
2. Create or select an ensemble.
3. Add a student by username where available.
4. Review roster and active member state.
5. Review aggregate reports.
6. Print/export the report surface.
7. Confirm removed or unauthorized access is blocked where a test persona exists.

Auth testers should run these only with disposable live credentials and provider configuration:

1. Sign up.
2. Sign in.
3. Request and complete password reset.
4. Test Sign in with Apple.
5. Export account data.
6. Delete the account and confirm local sign-out and backend cleanup.

iOS/native testers should:

1. Launch in simulator.
2. Complete onboarding.
3. Run demo practice.
4. Open settings; on compact iPhone simulators this may be under the `More` tab.
5. Open account screens.
6. Open legal/support surfaces.
7. Exercise denied microphone state.

Physical device validation still requires supported iPhone and iPad hardware, real brass input, quiet and noisy rooms, route-change checks where available, recording/playback/delete, and the protocol in `PHYSICAL_DEVICE_PROTOCOL.md`.

## Known Limitations

- Live Supabase email confirmation, password reset delivery, Apple OAuth, token refresh, identity deletion, and storage cleanup require disposable live credentials and provider setup.
- Vercel preview page-route automation remains blocked by Vercel Authentication unless a bypass is provided.
- Native iOS remains a simulator-verified app shell with generated demo takes in several product areas; it is not yet TestFlight/App Store ready.
- Signed archives, App Store Connect upload, legal metadata, and Apple review metadata require owner/account access.
- Physical microphone quality is not verified by simulator or browser automation.

## Privacy And Data Notes

- Test with disposable accounts and non-sensitive practice data.
- Do not upload real student rosters or private recordings until the owner has approved the beta data policy.
- Account export and account deletion surfaces exist. Live deletion and Supabase identity/storage cleanup still require live-provider validation before broad beta.
- Audio retention should be tested with explicit consent only.

## Bug Reports

Report bugs with:

- Browser/device and operating system.
- URL tested.
- Persona: guest, teacher/director, student, auth tester, or native simulator.
- Exact steps, expected result, actual result.
- Screenshot or screen recording when safe.
- Whether the issue involved microphone permission, recording, export, auth, WebSocket, or ensemble access.

Do not include passwords, provider tokens, private environment values, real user data, or sensitive recordings in reports.

Use `BETA_QA_GUIDE.md` for the friend-tester script, common tester fixes, accessibility checklist, and triage labels. Use `LIVE_AUTH_TEST_PLAN.md` for disposable live-account auth evidence, and `LOAD_ABUSE_SMOKE.md` for conservative load/abuse smoke checks.

## Rollback And Contact Process

- Stop beta testing if health, CORS, WebSocket, auth, account deletion, or data export fails.
- Follow `DEPLOYMENT_ROLLBACK.md` for Vercel, Render, and database rollback guidance.
- Owner must provide the final support/contact channel before inviting external testers.
