# Beta Load And Abuse Smoke

This is the closed-beta filename for `LOAD_ABUSE_SMOKE.md`. Use the detailed checklist there.

Key rule: run only small, owner-approved smoke checks. Do not stress production, create synthetic account spam, or upload large private recordings.

Core checks:

- repeated `/api/health`
- private endpoints reject unsigned access
- CORS allows only approved origins
- oversized/bad audio upload rejects cleanly with disposable accounts
- WebSocket rejects invalid or unauthenticated data without saving account data
- import file size limits are understandable to users
