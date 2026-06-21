# Web Control Manifest

Updated: 2026-06-21T05:24:54Z
Branch: `arya/final-web-completion`

This manifest covers shipping web routes and controls in the Phase 1 locked scope. The machine-readable companion is `web-control-manifest.json`.

## Result

Current result: local pass, production pending.

Dead-control fixes completed in this pass:

- Heat-map cells render as non-focusable read-only cells when no selection handler exists.
- Live microphone monitoring can be stopped from the visible mic control.
- Guest sessions can be deleted from the Sessions UI.
- Cloud export failures and Audio Lab clipboard failures now show visible status.
- Ensemble create/add buttons are disabled until required inputs exist and set guidance when invoked empty.
- Score Practice file inputs reset after import so the same file can be selected again.
- Theme selector is reachable on the auth gateway and Settings.

## Route Coverage

| Route | Persona | Primary controls | Success assertion | Browser test |
|---|---|---|---|---|
| `/` | unsigned, guest, returning account | email/password, provider buttons when configured, Continue as guest, theme selector, Privacy/Terms/Support | Gateway renders without app shell; guest enters `/home`; session restore redirects signed-in users | `root gateway starts guest practice and persists theme selection` |
| `/home` | guest/account | Start practice, coach/analytics links, recent sessions | Dashboard renders after guest/auth access | `critical routes render identifiable content` |
| `/practice` | guest/account | start/stop recording, mic start/stop, import recording, review link | Guest recording creates local reviewable session without protected API noise | `demo recording creates a reviewable session with playback surface` |
| `/metronome` | guest/account | start/stop, BPM, tap tempo, meter, subdivisions, ramp, mute/volume | Route renders and local E2E/accessibility passes | route/accessibility smoke |
| `/practice/score` | guest/account | camera, photos, files, drag/drop, paste, page selection, confirm/remove, preview toolbar | Route renders; file inputs reset after use; unsupported raw SVG rejected | route/accessibility smoke |
| `/sessions` | guest/account | filters, review, export, playback, guest delete | Guest sessions can be reviewed/exported/deleted locally | device simulation, release journey |
| `/sessions/:id` | guest/account | playback, CSV/JSON/audio export, heat map, note table | Guest review is visible and export controls respond | release journey, device simulation |
| `/analytics` | account/guest-safe | heat-map selection when data exists, interval segmented controls, date filters | No inert heat-map buttons outside selectable analytics context | device simulation |
| `/progress` | account/guest-safe | date/status views | Guest-safe insufficient-data state, no raw protected errors | route/accessibility smoke |
| `/coach` | account/guest-safe | plan/recommendation cards | Honest generated-from-local-data language | route/accessibility smoke |
| `/ensemble` | signed-in director/student, guest-safe | group select, create, add member, print/export | Server authorization rejects forbidden writes; empty controls do not no-op | `server-side ensemble authorization rejects forbidden writes` |
| `/settings` | guest/account | instrument, A4, guide mode, theme, sign-in/out, export, clear prefs, delete account, legal links | Export before delete visible; delete disabled for guests; sign-out errors surface | `settings exposes export before account deletion and legal links` |
| `/settings/audio-lab` | guest/account | mic monitor, calibration recording, copy diagnostics | Copy failures surface; mic can stop | route/accessibility smoke |
| `/privacy`, `/terms`, `/support` | public | legal/support links | Public routes remain reachable without guest/auth access | route/accessibility smoke |

## Remaining Production-Gate Checks

- Exact-SHA preview and production smoke for this branch after merge/deploy.
- Live account/provider controls remain hidden unless provider-specific env flags are enabled.
- Disposable live Supabase lifecycle tests remain owner-gated.
