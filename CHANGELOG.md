# Changelog

## Unreleased - arya/final-web-completion

Base SHA: `a8ce933a8ccfdac75b4244fe1c1bb2630655d14b`

- Added auth-first web launch at `/`, moved dashboard to `/home`, and added explicit guest access/deep-link handling.
- Added shared BrassTune design tokens and web theme selection with pre-paint theme initialization.
- Hardened visible web controls: mic stop, guest delete, export/copy status, non-interactive read-only heat-map cells, ensemble input gating, and score input reset.
- Added Vercel and API security headers, stricter WebSocket origin/auth behavior, JSON request caps, and audio upload format validation.
- Updated local E2E and device simulation for the gateway-first route model.
- Added current web scope, web control manifest, and pending production gate docs.

Production release: pending merge, deploy, exact-SHA smoke, tag, and GitHub prerelease.
