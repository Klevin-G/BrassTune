# Direct Production Deployment Checklist

Updated: 2026-07-24. Deployed application revision: `26683c82c42839016383fb9cab676c9a35d554ca`.

GitHub Actions is disabled. Do not wait for, trigger, or cite Actions checks for this candidate.

1. [x] Record final merged application SHA `26683c82c42839016383fb9cab676c9a35d554ca`.
2. [x] Reconfirm `20260724072904_account_deletion_maintenance_heartbeats.sql`; local and remote histories matched after the 2026-07-24 application.
3. [x] Deploy Render directly: `dep-d9hinqjeo5us73e9eqng`; `/api/ready` and `/api/version` pass with the exact SHA.
4. [x] Deploy Vercel: `dpl_5izYQzxQu4ZjwUn6gJxrHYArBD8v`; `https://brasstune.vercel.app` serves the production artifact.
5. [x] Run hosted smoke: all 8 checks passed; provider error queries returned no errors for the checked window.
6. Keep Apple live provider setup, signing, and physical-device microphone validation as separate external gates.
7. [x] Create the professor outreach set in `brasstune1@gmail.com`: 44 unique drafts verified; none sent.

## Completion record

The web/backend production record and Gmail drafting record are complete. Apple/provider signing, physical-device audio, and disposable-account lifecycle remain separate gates.
