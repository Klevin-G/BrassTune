# Beta Feedback Triage

Status: lightweight process for closed-beta feedback. Do not add third-party analytics or tracking by default.

## Privacy Rules

Do not collect real student data, passwords, provider keys, reset links, tokens, or sensitive recordings. Screenshots should avoid personal details.

## Severity

- `P0`: data exposure, account deletion/export failure, auth loop blocking all testers, production unavailable.
- `P1`: guest practice broken, live microphone unusable on supported hardware, session review missing, teacher/student authorization bug.
- `P2`: confusing copy, layout overflow, accessibility issue, slow cold start, import/export friction, flaky WebSocket.
- `P3`: visual polish, nonblocking copy, feature request, nice-to-have instrumentation.

## Required Fields

- URL and build/deployment if known
- Device, OS, browser, or simulator
- Persona: guest, student, teacher, signed-in user
- Steps to reproduce
- Expected and actual behavior
- Safe screenshot/log evidence
- Category: auth, mic, recording, WebSocket, import, export, ensemble, native, mobile layout

## Cadence

Review P0/P1 immediately during closed beta. Batch P2/P3 into the next hardening pass unless they block a tester journey.
