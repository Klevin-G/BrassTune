# TestFlight upload — current archive/export procedure
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23 UTC.

This document describes the current source candidate, `1.0.1 (6)`. The exact
candidate was archived, exported, distribution-signed, and uploaded on
2026-08-23; TestFlight processing completed and build 6 is **Ready to Submit**.
Version `1.0.1` exists in App Store Connect with build 6 attached. These facts
do not prove processed-build physical behavior, hosted backend correctness, or
App Review acceptance.

## Candidate-version rule

The archive/export script uses the version and build already declared by the
Xcode project. Its export options set
`manageAppVersionAndBuildNumber=false`, so it does not replace the candidate
version or build number. Keep build `6` bound to the exact reviewed candidate.
If a replacement archive is required, manually increment the project build
number before archiving and treat the replacement as a new candidate; do not
reuse or let the export tool auto-manage build `6`.

## Archive and export

The script verifies public production runtime configuration, archives the
Release app with automatic signing, and exports a signed IPA. It does not upload
to TestFlight by itself. Set the required values in the backend/local execution
environment without committing a real `.env` file:

```bash
APPLE_TEAM_ID=YOURTEAMID \
BRASSTUNE_BUNDLE_ID=com.aryasalem.BrassTune \
BRASSTUNE_SUPABASE_URL=https://<20-character-project-ref>.supabase.co \
BRASSTUNE_SUPABASE_PUBLISHABLE_KEY=<complete-public-publishable-key> \
BRASSTUNE_RELEASE_OUT=<dedicated-release-evidence-directory> \
scripts/ios/build-testflight.sh
```

The output directory must be a dedicated release-evidence directory. Preserve
the resulting archive, IPA, export diagnostics, and dSYM evidence together with
the exact source revision and the `1.0.1 (6)` version/build inspection.

## Upload and candidate closure

The generated IPA was uploaded through Xcode and completed TestFlight processing.
Do not use a simulator, a build-only archive, or an earlier TestFlight build as
a substitute for physical processed-build validation. The remaining candidate
closure is hosted exact-backend smoke followed by physical validation as
applicable; Add for Review/submit is intentionally held until the backend
revision gate passes.

Use [TESTFLIGHT_HANDOFF.md](TESTFLIGHT_HANDOFF.md) for release-gate context and
[APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) for App Store metadata,
privacy, and human-attestation requirements. Recheck those historical records
against the final candidate before acting.

## Historical record

The former `0.1.0 (1)` instructions and references to `1.0.0 (2)` were
superseded. They are not valid upload instructions for this candidate and must
not be used to select, replace, or describe build `6`.
