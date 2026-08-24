# TestFlight upload — current archive/export procedure
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23 UTC.

## Current replacement-candidate status

Version `1.0.1` is now **Developer Rejected / Removed** and build 7 remains
associated. The local Classes MVP requires a new build 8 candidate. No build 8
archive, export, upload, TestFlight processing, build selection, or
resubmission has occurred. Do not describe build 7 as Waiting for Review.

The project settings now declare `MARKETING_VERSION 1.0.1` and
`CURRENT_PROJECT_VERSION 8`. This is configuration only, not candidate
evidence. Nandy’s iPhone 15 Pro Max / iOS 26.6.1 completed the physical
student/owner/assistant fixture UI workspaces `1/1`, zero failed/skipped. This
is not live hosted multi-account sync, migration, archive, or release evidence.

Before creating build 8, apply and verify the pending Classes migration in the
authorized environment, complete disposable live consent/class/privacy checks,
and preserve the completed implementation-snapshot `26/26` UI evidence plus
the final dedicated Classes `1/1` UI evidence. The build number is already
configured as `8`; record the exact source revision and archive
evidence, upload through Xcode, wait for processing, select build 8 for
version `1.0.1`, refresh review notes/privacy answers as needed, then submit.

This document describes submitted candidate `1.0.1 (7)`, archived from native
source `d371100` on `arya/final-physical-release-20260823`. That source is
distinct from deployed web/backend implementation `98fd1d9e7b85add63537e2e3dfe6d0`.
Archive/export and upload succeeded; TestFlight reports build 7 **Ready to
Submit**. Version `1.0.1` has build 7 attached and is **Waiting for Review**
with manual release selected. These facts do not prove App Review approval.

## Candidate-version rule

The archive/export script uses the version and build already declared by the
Xcode project. Its export options set
`manageAppVersionAndBuildNumber=false`, so it does not replace the candidate
version or build number. Keep build `7` bound to the exact reviewed candidate.
If a replacement archive is required, manually increment the project build
number before archiving and treat the replacement as a new candidate; do not
reuse or let the export tool auto-manage build `7`.

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
the exact source revision and the `1.0.1 (7)` version/build inspection. The
final IPA SHA-256 is `640511f5a15f579500f86710393a6f661ced4cff87a64f00b8ccbe689bea2782`;
the matching app/dSYM UUID is `77D84475-6D50-3D94-B842-290431F0D74D`.

## Upload and candidate closure

The generated IPA was uploaded through Xcode and completed TestFlight processing.
Its strict distribution signature is valid for `Apple Distribution: Arya Salem`
(team `8S79RLTSWV`), bundle `com.aryasalem.BrassTune`, and production
environment/API configuration. The review notes were replaced, and version
`1.0.1` with build 7 was submitted. Do not use a simulator, a build-only
archive, or an earlier TestFlight build as a substitute for unavailable
attended acoustic, accessory-route, or full accessibility validation.

Use [TESTFLIGHT_HANDOFF.md](TESTFLIGHT_HANDOFF.md) for release-gate context and
[APP_STORE_CHECKLIST.md](APP_STORE_CHECKLIST.md) for App Store metadata,
privacy, and human-attestation requirements. Recheck those historical records
against the final candidate before acting.

## Historical record

The former `0.1.0 (1)` instructions and references to `1.0.0 (2)` or
`1.0.1 (6)` were
superseded. They are not valid upload instructions for this candidate and must
not be used to select, replace, or describe build `7`.
