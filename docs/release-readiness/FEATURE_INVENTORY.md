# Feature Inventory

Date: 2026-06-18

| Area | Current Status | Evidence | Remaining Gap |
|---|---|---|---|
| Guest practice tuner | Implemented on web; local browser journeys pass | `frontend/src/pages/PracticePage.tsx`, `npm run e2e:local` | Physical microphone quality requires device protocol |
| Recording lifecycle | Web start/stop is guarded by explicit states and disabled controls while busy | `useSessionRecorder`, `SessionControls`, Playwright recording journey | More component-level rapid-click tests would improve coverage |
| Playback | Web playback lazy-loads audio on user action and revokes object URLs | `SessionAudioPlayer.tsx` | Add component test for lazy fetch/revoke |
| Local media import | Preflight size/type validation, cancel, and best-effort partial cleanup added | `LocalMediaImportPanel.tsx`, `localMediaAnalysis.test.ts` | Browser codec support still needs device/browser QA |
| Account auth | Web/native surfaces exist for email/password, reset, Apple, sign-out, and deletion | `AuthPage.tsx`, `AuthContext.tsx`, Swift settings views | Live Supabase and Apple provider flows blocked by credentials/config |
| Account export/deletion | Backend account export includes profile, sessions, memberships, invitations, recommendations; deletion preflights Supabase before local delete | `routes.py`, `test_hardening.py` | Needs live Supabase cleanup test and eventual deletion outbox/retry |
| Teacher/director dashboard | Web supports group list/create/select/add and manager-only aggregate reports | `EnsemblePage.tsx`, backend tests | Rename/archive/delete/invite acceptance remain incomplete |
| Student ensemble view | Active members can view group roster but not aggregate reports | `routes.py`, `EnsemblePage.tsx` | Student acceptance/invitation workflow not complete |
| Shared domain parity | Backend/frontend/Swift fixture smoke passes | `swift test`, Vitest, pytest | Full cross-runtime fixture matrix still limited |
| Native SwiftUI app | Native app target, tests, UI smoke, unsigned Debug/Release simulator builds pass | `swift/BrassTuneApp`, xcodebuild results | Production config, signing, Apple capability, live auth, native mic pipeline remain incomplete |
| CI/security | Backend/frontend/security/Swift/device workflows exist with bounded timeouts and artifacts | `.github/workflows/*` | GitHub environment protection/reviewers require repo settings |
| Hosted deployment | Vercel root/deep link and Render health/CORS pass | curl and hosted Playwright smoke | Hosted WebSocket handshake fails; current production lacks this branch content |
