# Final Web Scope

Updated: 2026-06-21T05:24:54Z
Branch: `arya/final-web-completion`
Base SHA: `a8ce933a8ccfdac75b4244fe1c1bb2630655d14b`

## Locked Scope

Phase 1 is web/backend only. Swift application source remains out of scope until the web production completion gate is passed.

Included:

- Authentication-first launch at `/`, dashboard at `/home`, session restoration, safe private deep-link return, sign-out return to gateway, and Continue as guest.
- Account-disabled guest-first release behavior with no raw provider, backend, or environment errors in user-facing copy.
- Shared BrassTune theme token source and web themes: System, Brass Night, Brass Day, Liquid Brass - Clear, Liquid Brass - Tinted, High Contrast.
- Guest microphone practice, recording, playback, local persistence, local delete, export, and review routes.
- Metronome, Score Practice import/preview, conservative score language, session review, analytics, progress, coach, settings, legal/support, and ensemble surfaces in the defined beta scope.
- Web/backend security controls: exact CORS origins, WebSocket origin/query-token/auth hardening, request size and rate limits, audio upload format validation, Vercel/API security headers, dependency/SAST checks, and no tracked secrets.
- Browser, accessibility, responsive, and device-simulation validation.
- Release docs, rollback/smoke scripts, and current evidence.

Out of scope for Phase 1 unless a critical/high security or data-loss defect is found:

- SwiftUI/native implementation.
- Live Supabase, Google, or Apple provider lifecycle without owner-provided disposable credentials.
- Paid resources, production infrastructure changes outside existing projects, App Store/TestFlight submission, and physical-device brass validation.
- New unrelated feature expansion beyond the locked beta web scope.

## Current Status

Local web/backend gates are green on this branch. Production completion is not yet certified for this branch because it has not been pushed, merged to `main`, deployed to Vercel/Render, exact-SHA verified, tagged, or released.

Required before writing `WEB PRODUCTION COMPLETION GATE: PASSED`:

- Branch pushed and PR opened/merged normally into `main`.
- Required CI green on the exact PR head.
- Vercel production READY for the merge SHA.
- Render production live for the matching backend SHA.
- Strict production smoke rerun against the new deployments.
- Rollback target and release tag recorded.
