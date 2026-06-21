# Interaction Matrix

Updated: 2026-06-21T00:13:54Z

This matrix tracks release-critical controls and their verification status. The machine-readable companion is `interaction-matrix.json`.

| Platform | Route/screen | Control | Expected action | Implementation | Success assertion | Error assertion | Automated coverage | Status |
|---|---|---|---|---|---|---|---|---|
| Web | `/practice` | Start recording | Opens mic or demo input, starts session, starts audio capture | `frontend/src/pages/PracticePage.tsx` | Session timer/recording state starts | Mic denied shows guest/demo fallback | Local E2E, build | Pass |
| Web | `/practice` | Stop recording | Stops session and saves local/cloud audio truthfully | `frontend/src/pages/PracticePage.tsx` | Summary/audio state updates only after persistence | Save failure stays visible | Local E2E, unit coverage | Pass |
| Web | `/practice` | Open metronome | Navigates to metronome tool | `frontend/src/pages/PracticePage.tsx` | `/metronome` route renders | Route 404 would fail E2E | Local E2E | Pass |
| Web | `/practice` | Open score practice | Navigates to score practice tool | `frontend/src/pages/PracticePage.tsx` | `/practice/score` route renders | Route 404 would fail E2E | Local E2E | Pass |
| Web | `/metronome` | Start/stop | Schedules/stops Web Audio clicks | `frontend/src/pages/MetronomePage.tsx` | Running/ready status toggles | Unsupported browser message | Build, route E2E | Pass |
| Web | `/metronome` | BPM +/- and numeric BPM | Updates current and running scheduler BPM | `frontend/src/pages/MetronomePage.tsx` | BPM display changes | Clamp bounds hold | Build | Pass |
| Web | `/metronome` | Accent/ramp settings | Running scheduler reads latest setting refs | `frontend/src/pages/MetronomePage.tsx` | Queue behavior uses refs | No stale closure for ramp/accent | Build | Pass |
| Web | `/practice/score` | Choose files/photos/drop/paste | Validates PDF/image contents and imports locally | `frontend/src/pages/ScorePracticePage.tsx` | Page appears in reader | Unsupported/oversized files show status | Domain tests, build | Pass |
| Web | `/practice/score` | PDF page navigation | Renders previous/next PDF page through PDF.js canvas | `frontend/src/pages/ScorePracticePage.tsx` | Page counter/canvas update | Render failure status shown | Build | Pass |
| Web | `/practice/score` | Zoom/rotate/focus/remove | Applies reader transform or render params; toggles focus; deletes page | `frontend/src/pages/ScorePracticePage.tsx` | Visual state/page list changes | Missing selected page handled | Build | Pass |
| Web | `/auth/*` | Email/password actions | Calls Supabase when configured; hides when disabled | `frontend/src/state/AuthContext.tsx`, `frontend/src/pages/AuthPage.tsx` | Friendly account messages | Raw provider/env errors mapped | Build | Pass |
| Web | `/auth/*` | Google/Apple provider buttons | Starts OAuth when configured | `frontend/src/state/AuthContext.tsx`, `frontend/src/pages/AuthPage.tsx` | Redirect starts | Provider failures mapped | Build; live provider externally gated | Partial |
| Backend | `/api/sessions/*/samples` | Save pitch frame | Canonicalizes note/cents/status server-side | `backend/app/services/session_service.py` | Forged labels overwritten | Instrument mismatch rejected | Backend hardening tests | Pass |
| Backend | `/api/users/me` | Delete account | Cleans local data first; records deletion job; then external identity cleanup | `backend/app/api/routes.py` | Job completed or queued | Local cleanup failure returns 503 and does not delete identity | Backend hardening tests | Pass |
| Backend | `/api/ensemble/*` | Teacher/student ensemble actions | Enforces manager roles and active membership windows | `backend/app/api/routes.py` | Allowed operations succeed | Forbidden access fails server-side | Backend hardening tests | Pass |
| Hosted | Production smoke | Web/API/WS smoke | Verifies deployed web/backend behavior | `scripts/hosted-smoke.mjs` | Root, health, CORS, WS hardening pass | Query-token and bad-Origin must reject | Hosted smoke | Red gate |
| Native | App tabs/buttons | Practice/sessions/analytics/settings | Simulator app launches and smoke navigation works | `swift/BrassTuneApp` | Simulator tests pass | Native real mic/score/metronome not proven | XcodeBuildMCP evidence | Partial |

Known exclusions from this matrix are tracked as release gates or post-release backlog, not hidden as passed controls.
