# TestFlight upload — current archive/export procedure
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-24 UTC.

## Current submitted candidate

Candidate `1.0.1 (8)` is implementation/archive/deployment SHA
`5acfa2ecc6b7403d1572d7382d41357c8ccc2fb4` (PR 32 merged). A later SHA may
contain docs-only changes and does not change candidate identity. The archive
uses canonical Supabase `yznziwe`, bundle `com.aryasalem.BrassTune`, Apple
Distribution team `8S79RLTSWV`, `get-task-allow=false`,
`beta-reports-active=true`, and a privacy manifest. IPA SHA-256 is
`cade0c9842e99f2e77e1f1b27e408460a331b880beb59f59d7f11f8f579ffe8c`; matching
app/dSYM UUID is `8378AB6E-EA6E-32B3-A26E-F781A481518D`.

Archive/export evidence is under
`/Users/aryasalem/Library/Application Support/BrassTune/ReleaseEvidence/AppStoreCandidate-2026-08-24-1.0.1-8`.
Upload succeeded; processing is Complete/Ready to Submit; build 8 is selected;
metadata and review notes are updated. Submission
`14b8ba6a-fe40-421f-ab61-790bbe51cb08` was submitted by Arya Salem on August
24 and is **Waiting for Review** with manual release. This is not approval.
Build 7 is historical removed/superseded.

## Candidate-version rule

The archive/export script uses the version and build declared by the Xcode
project. Its export options set `manageAppVersionAndBuildNumber=false`; do not
allow a later archive to overwrite or be represented as this build-8 candidate.

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
the exact source revision and the `1.0.1 (8)` version/build inspection.

## Upload and candidate closure

The generated IPA was uploaded through Xcode and completed TestFlight processing.
The review notes were updated and version `1.0.1` with build 8 was submitted.
Do not use a simulator, a build-only
archive, or an earlier TestFlight build as a substitute for unavailable
attended acoustic, accessory-route, or full accessibility validation.

Use [TESTFLIGHT_HANDOFF.md](TESTFLIGHT_HANDOFF.md) for release-gate context and
[APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) for App Store metadata,
privacy, and human-attestation requirements. Recheck those historical records
against the final candidate before acting.

## Historical record

Build 7 and earlier references are historical only and must not be used to
describe, select, or replace build 8.
