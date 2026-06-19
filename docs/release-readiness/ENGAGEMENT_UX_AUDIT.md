# Engagement UX Audit

Date: 2026-06-18

## Fixed Now

- Replaced production-facing `MVP`, `Developer testing`, `seeded`, `FastAPI`, and Supabase-env copy in user-visible web surfaces with product-safe guest practice/account messaging.
- Replaced native tester-facing `fixture` labels with product-safe demo-take copy while keeping the technical limitation documented in release reports.
- Hid demo-data repair/reset controls behind `VITE_ENABLE_INTERNAL_TOOLS=true`; normal builds show practice, export, legal, support, and account controls.
- Removed `/dev/calibration`; Audio Lab remains at `/settings/audio-lab` as a user-facing diagnostics surface.
- Added support access in Settings and kept Privacy/Terms/Support routes in the local browser matrix.
- Moved native Settings Data/export/delete controls above tuner/account controls so beta testers can find account lifecycle actions immediately, including on compact iPhone tab bars where Settings is under `More`.
- Made recording controls visibly busy during start/stop/upload transitions.
- Preserved auth-shell focus by excluding the floating tab bar from auth routes and updating device simulation expectations accordingly.

## Current First-Run Flow

- Onboarding asks for instrument, A4 reference, guided audio vs microphone mode, lock-state interpretation, and first practice take.
- Guest practice is available when account sign-in is not configured.
- Local browser journeys verify route rendering, onboarding focus trap, practice recording, review navigation, settings export/delete surfaces, and legal/support links.

## Remaining UX Gaps

- Teacher dashboard still needs production-grade rename/archive/delete, invitation acceptance, roster search, role/instrument edit controls, and report download beyond print.
- Live auth error states need validation with real Supabase email confirmation, password reset links, Apple OAuth cancellation, and expired token recovery.
- Native app still uses fixture practice/audio behavior; production microphone capture and real API-backed ensemble workflows are not complete.
- Public support URL/email and final legal wording require owner/legal input.
