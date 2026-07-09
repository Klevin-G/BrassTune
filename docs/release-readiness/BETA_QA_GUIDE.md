# Closed-Beta QA Guide

Status: operational guide for owner-controlled closed-beta testing. BrassTune remains a closed-beta candidate; live provider, App Store, and physical-device gates remain outside this guide.

## Friend Tester Script

Use disposable data only.

1. Open `https://brass-tune.vercel.app`.
2. Complete onboarding and choose an instrument.
3. Run the demo tuner, start a take, stop it, and open session review.
4. Deny microphone permission, then confirm the recovery copy is understandable.
5. Allow microphone permission and play a short long tone if testing on real hardware.
6. Visit Sessions, Analytics, Progress, Coach, Ensemble, Settings, Privacy, Terms, and Support.
7. Export session/account data where available.
8. On mobile Safari, confirm navigation, safe-area spacing, buttons, meters, and dialogs are usable.
9. Report any confusing copy, layout issue, slow load, missing state, broken link, or unexpected auth prompt.

## Common Tester Fixes

- If a preview URL shows Vercel Authentication, use production or an owner-approved share/bypass URL.
- If the app appears stale, hard refresh or clear site data for the tested URL.
- If microphone access fails, confirm the browser is on HTTPS and the OS/browser permission is allowed.
- If live tuning is unavailable, capture whether `/api/health` works and whether Audio Lab shows `wss://brasstune-u8qj.onrender.com`.
- If sign-up/reset does not send email, stop auth testing and check Supabase email/SMTP/provider configuration with the owner.
- If Apple sign-in fails, record the visible error and stop; do not retry with personal Apple IDs until the provider setup is confirmed.

## Feedback Triage

Use one issue per problem.

- `P0`: data loss, unauthorized access, account deletion/export failure, production unavailable, or auth loop blocking all testers.
- `P1`: core practice/session review broken, live mic unusable on supported device, teacher/student authorization bug, or repeated WebSocket failure.
- `P2`: confusing workflow, layout overflow, accessibility issue, slow page, analytics/recommendation quality problem, or beta-support friction.
- `P3`: copy polish, visual refinement, nonblocking feature request, or instrumentation idea.

Capture URL, device/browser, persona, steps, expected result, actual result, screenshot when safe, console/network errors when available, and whether the issue used demo, microphone, auth, export, ensemble, or native simulator.

## Accessibility Checklist

- Keyboard can reach every interactive control without traps.
- Focus is visible after route changes, dialogs, menus, and form errors.
- Screen reader labels describe icon-only buttons, meters, status messages, and destructive actions.
- Error/status messages are announced or discoverable without visual-only cues.
- Text remains readable at browser zoom and mobile viewport widths.
- Color is not the only signal for pitch lock, warnings, errors, or disabled controls.
- Touch targets are usable on small phones.
- VoiceOver on iOS Safari can complete onboarding, practice, session review, settings, export, and auth pages.

Record unresolved issues in the beta tracker before expanding the tester group.
