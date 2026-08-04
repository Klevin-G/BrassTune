# Web Production Completion Gate

Updated: 2026-08-04. Historical deployed revision: `26683c82c42839016383fb9cab676c9a35d554ca`. It predates Apple web-provider enablement and is not evidence of the current hosted release candidate.

The historical web/backend production gate passed for that exact revision. Local suites passed (`286 passed, 11 skipped` backend; `253/253` frontend), the production frontend build passed, linked Supabase migrations matched through `20260724072904`, Render deployment `dep-d9hinqjeo5us73e9eqng` was live, Vercel deployment `dpl_5izYQzxQu4ZjwUn6gJxrHYArBD8v` was ready on the canonical alias, and all 8 hosted smoke checks passed. GitHub Actions remained disabled and was not used.

Google and Apple provider buttons remain visible in the UI. Google is enabled in the linked Supabase project. Apple is owner-confirmed enabled in Apple Developer and Supabase; the production frontend environment must use `VITE_AUTH_APPLE_ENABLED=true`. Hosted smoke now requires an enabled `Continue with Apple` button alongside Google and email, followed by a live web authorize/callback test, before a new deployed revision may satisfy this gate.

This gate does not establish physical-device audio or disposable-account lifecycle completion. It must be re-run against the exact current deployed frontend and backend SHAs before release closure.
