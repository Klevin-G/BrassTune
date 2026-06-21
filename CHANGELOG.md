# Changelog

## 0.1.0-beta.1 - 2026-06-21

Release tag: `web-beta-2026.06.21.1`
Final web main SHA: `6acb91d54a734e722ed937590aecb51dec53543c`

- Added auth-first web launch at `/`, moved dashboard to `/home`, and added explicit guest access/deep-link handling.
- Added shared BrassTune design tokens and web theme selection with pre-paint theme initialization.
- Hardened visible web controls: mic stop, guest delete, export/copy status, non-interactive read-only heat-map cells, ensemble input gating, and score input reset.
- Added Vercel and API security headers, stricter WebSocket origin/auth behavior, JSON request caps, and audio upload format validation.
- Updated local E2E, hosted smoke, and device simulation for the gateway-first route model.
- Added web scope, control manifest, production gate, and release evidence docs.

Production release: deployed to Vercel `dpl_6pScePaqbs8fYYD44wanhdgZkAPN`; Render backend verified live by security headers and hosted smoke.
