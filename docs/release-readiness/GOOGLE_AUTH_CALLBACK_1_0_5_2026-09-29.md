# Native Google sign-in callback — 1.0.5 (15) physical evidence (2026-09-29)
Project attribution: Kelvin Guo, Arya Salem.

> October 6 follow-up: the public App Store lookup now reports 1.0.5, released
> September 29. New server traces contain build-15 callback flows without a
> subsequent token exchange, so the stale-install explanation below is not a
> complete explanation of the recurring symptom. The connected phone passed
> fresh sign-in checks, but its collected archive does not contain the earlier
> failure windows. See [the October 6 investigation](GOOGLE_AUTH_FOLLOWUP_2026-10-06.md)
> for the evidence and the separately reproduced empty-fragment compatibility
> defect. Historical results below are retained as recorded, not current release
> or universal root-cause proof.

Scope: the recurring native error "The sign-in callback could not be verified.
Start sign-in again." on the USB-connected iPhone. Release status: **1.0.5 (15)
submitted; Waiting for Review**. Automatic release after Apple approval is
selected. The physical Google-auth gate passed before upload/submission.
Public release is not yet verified.

## Device and installs

- Device: Nandy's i15 Pro Max (iPhone16,2), iOS 26.6.2, wired, Developer Mode
  on. CoreDevice `4F79BC8A-8E95-58FA-8513-2B0E5EF1D1CB`, Xcode destination
  `<physical-device-id>`.
- Before: `com.aryasalem.BrassTune` **1.0.0 (5)** (stale developer-signed
  install) and `com.aryasalem.BrassTune.dev` 1.0.4 (14).
- Final candidate installed in place (no uninstall, data kept):
  `com.aryasalem.BrassTune` **1.0.5 (15)**, Release, `BRASSTUNE_ENV=production`,
  callback scheme `com.brasstune.auth`, Supabase `yznziwewxrlwnwiynlvl`,
  signed "Apple Development" with the team provisioning profile.
  Executable SHA-256 `224e0e40ef9303c4f8f94e932000095b1ae94698a87ec46a288e0e911ea0a947`.

## Root cause

The failing observations occurred while the **stale production install
1.0.0 (5)** was installed. Supabase returned a normal code-and-state callback,
but no token exchange followed. Installing current source restored the exchange
on the same phone. The exact failure point in the old binary remains unproven.

- Supabase edge logs attribute both failing flows (2026-09-27 20:48 UTC and
  2026-09-29 04:01 UTC) to this phone's WebKit (iOS 26.6.2) with
  `redirect_to=com.brasstune.auth://oauth/google?state=…`. That is the
  production bundle, which was 1.0.0 (5) on this phone.
- In both flows Supabase returned a normal success redirect (`code` + `state`,
  no error). The app never sent `POST /token`, so the stale binary rejected the
  callback locally before the PKCE exchange.
- The same production flow from build 14 on another phone (iOS 27.0,
  2026-09-27 19:21 UTC) exchanged successfully.
- After the current production source was installed over 1.0.0 (5), the first
  real attempt on this phone exchanged the code (`POST /token grant=pkce 200`
  from `BrassTuneApp/14`, 04:36:51 UTC).
- Live configuration was read-only checked: the Google provider is enabled,
  and the allow-list contains `com.brasstune.auth://oauth/google\?state=*` and
  its `.dev` twin. It matches `supabase/config.toml`.
- The 1.0.0 (5) binary is not in Git (it was built between `ed4d8b2` and
  `bc79af4`) and was not recovered, so the exact guard it failed is unproven.
  The fix is to replace that install, not to relax validation.

## Code changes in 1.0.5 (15)

`swift/BrassTuneApp/BrassTuneApp/AuthService.swift`:

1. **Provider-error mirror, evidence-backed.** Live GoTrue v2.197.0 error
   redirects omit an empty `error_description` from the `#…&sb=` fragment and
   double-encode values containing `:` or `/`. Real provider errors
   (`access_denied`, `server_error: Unable to exchange external code…`) were
   therefore misreported as "callback could not be verified". The fragment
   now matches the query either directly or after one decoding step. The
   `error` value, `sb` marker, allowed field names and counts are still exact.
   This path never exchanges a code.
2. **Success shape tightened.** A success callback must be exactly one `state`
   and one `code`, with no fragment and no other field. A stray `error_code`
   or `error_description` beside a code fails closed.
3. **Value-free rejection diagnostic.** On `oauthCallbackInvalid`, the app logs
   scheme/host/path agreement, whether the state matched, counts for the fixed
   names `code/state/error/error_code/error_description/sb`, and an unknown-field
   count. It never logs callback-supplied names or any value.

State, PKCE (S256 verifier/challenge), scheme and bundle binding are unchanged.
Version: `MARKETING_VERSION 1.0.5`, `CURRENT_PROJECT_VERSION 15`.

## Automated tests (iPhone 17 Pro Simulator, iOS 26.5)

- Auth subset (AuthReliabilityTests plus 10 Google/OAuth tests): **17/17 pass**.
- Full `BrassTuneAppTests`: **324/324 pass**.
- New tests:
  - Live-captured Supabase error shapes.
  - Contradictory success fields.
  - The diagnostic contains no names or values.
  - `testGoogleServiceProviderErrorAndMalformedCallbacksMakeZeroRequestsAndWriteNoCredential`:
    9 cases, each with **0 network requests** and **no stored credential**.
- `scripts/verify_release_auth_config.sh` and `scripts/test_release_auth_config.sh`
  pass.

## Physical gate on the 1.0.5 (15) candidate

Harness: `BrassTuneAppUITests/PhysicalGoogleAuthGateUITests.swift`. It is opt-in
(`TEST_RUNNER_BRASSTUNE_PHYSICAL_GATE=1`) and skipped on Simulator. It drives the
installed production bundle and passes no reset or fixture arguments. It never
types into Google and stops for passwords, verification steps or profile
forms. Recorded outcomes are value-free; screenshots are kept only on failure.

**Do not run the whole class.** Its steps depend on state. Run one method at a
time, in this order:

```
TEST_RUNNER_BRASSTUNE_PHYSICAL_GATE=1 xcodebuild test-without-building \
  -project swift/BrassTuneApp/BrassTuneApp.xcodeproj -scheme BrassTuneAppUISmoke \
  -destination "id=<discovered device id>" \
  -only-testing:BrassTuneAppUITests/PhysicalGoogleAuthGateUITests/<method>
```

1. `testGoogleSignInCompletesInProductionApp` (starts signed out)
2. `testColdLaunchRestoresSignedInSession`
3. `testSignOutThenColdLaunchStaysSignedOut`
4. `testGoogleCancelThenRetrySucceeds` (starts signed out)
5. `testColdLaunchRestoresSignedInSession`

Results (UTC), in execution order. Result-bundle numbers skip 6 and 9.

| Run | Step | Result |
| --- | --- | --- |
| step1 | Google sign-in | **Harness failure**: XCUITest query timeout while polling the closing browser sheet. Server shows sign-in completed at 04:45:22. The harness was changed to check only app screens. |
| step2 | Cold-launch restore | Pass: `settings_signed_in=true`, `cold_launch=restored_signed_in` |
| step3 | Sign-out, signed-out cold launch | Pass: `sign_out=gateway;signed_out_cold_launch=gateway` |
| step4 | Google sign-in | Pass: `google_sign_in=returned_signed_in` (04:50:14) |
| step5 | Cancel/retry | **Precondition failure**: started signed in (operator ordering error) |
| step7 | Sign-out, signed-out cold launch | Pass |
| step8 | Cancel/retry | **Harness race**: the already-approved Google account completed in about 1 s, before the in-sheet cancel. Sign-in completed at 04:51:58. The harness now cancels at the system prompt. App source was not changed. |
| step10 | Sign-out, signed-out cold launch | Pass |
| step11 | Cancel then retry | Pass: `cancel_point=system_prompt`, no "could not be verified" notice, `second_google_sign_in=returned_signed_in` (04:53:36) |
| step12 | Cold-launch restore | Pass |

Sanitized Supabase auth trace (`device-gate-1.0.5-15/supabase-auth-trace-sanitized.txt`):

- 4 Google PKCE exchanges, each `/authorize` → `/callback 302` →
  `POST /token grant=pkce 200` → `Login google`.
- Backend verification `GET /user 200` (`Python-urllib`, the Render API) after
  each exchange and on restore.
- 3 sign-outs revoked server-side (`POST /logout 204`).
- No callback or token errors.
- Duplicate callbacks: none observed. Each flow shows one `/callback`, and
  retries after cancel start a new state/verifier pair.

Limitations:

- One Google account that had already authorized the app. No first-consent
  screen, password entry or 2-Step challenge was exercised.
- The simulator results don't stand in for the device, and the device results
  cover only this phone.
- Backend/frontend suites, shared `BrassTuneCore` package tests and broader
  audio/UI journeys were not rerun: this task changed native auth, its tests,
  versioning and evidence only. Unrelated pre-existing web/backend edits were
  preserved and are not claimed as validated by this auth work.

### Diagnostic 1.0.4 (14) reproduction (not release proof)

- Before the version bump, current source with the diagnostic was installed
  over 1.0.0 (5).
- That run showed the real success exchange at 04:36:51.
- Cold restore and sign-out also passed there.
- Harness faults on that build:
  - A Swift 6 isolation compile error.
  - A false password detection: the harness matched the app's own email form.
  - An ambiguous "Not now" query.
  - A wrong-scheme first automation attempt (`BrassTuneApp` scheme lacks UI tests).

## Artifacts (private, not in Git)

`~/Library/Application Support/BrassTune/ReleaseEvidence/GoogleAuthCallback-1.0.5-15-2026-09-29/`:

- `device-gate-1.0.5-15/`: per-step logs and `.xcresult`, plus the sanitized
  Supabase trace. The result bundles contain screen recordings that may show
  the account address; keep them private.
- `device-repro-1.0.4-14/`, `unit/`, `candidate-source-fingerprint.txt`,
  `apps-after15.json`, `build-prod15.log`.
- `archive-export.log`, `BrassTuneApp.xcarchive`, `ExportOptions.plist`
  (`destination=export`) and `export/BrassTuneApp.ipa`. This export step did not
  upload; the subsequent Codex upload receipt is recorded below.
  - Produced by `scripts/ios/build-testflight.sh`: ARCHIVE SUCCEEDED, EXPORT
    SUCCEEDED.
  - Signed "Apple Distribution: Arya Salem (8S79RLTSWV)" with "iOS Team Store
    Provisioning Profile: com.aryasalem.BrassTune".
  - `com.aryasalem.BrassTune` 1.0.5 (15), `BRASSTUNE_ENV=production`, scheme
    `com.brasstune.auth`.
  - IPA SHA-256 `2a5e47902b195baac9d64b78f234b80fdfa629d3214d6f1b6cdf08a69f37800c`.
  - The phone ran the development-signed Release build of the same frozen app
    source; the recorded app source fingerprints and `project.pbxproj` match
    `candidate-source-fingerprint.txt`. The distribution IPA itself was not
    installed on the device.

## Independent review and upload

- Codex independently read the unit and physical result logs, verified the
  installed production bundle/version with `devicectl`, and checked the
  distribution IPA using `codesign --verify --deep --strict --verbose=2`.
  The signature passed and identified Apple Distribution, team `8S79RLTSWV`.
- IPA version/build, production environment/API, callback scheme and SHA-256
  matched the archive handoff. No environment files, private-key files or
  test-result bundles were present in the IPA member inventory.
- Final independent auth review found no remaining code/runtime blocker in
  this scope. The root-cause wording above was qualified as requested.
- `git diff --check` passed. Existing unrelated dirty work was preserved.
  No Git commit, push, tag or merge was performed.
- Apple upload used `xcodebuild -exportArchive` with
  `CodexUploadOptions.plist` (`destination=upload`,
  `manageAppVersionAndBuildNumber=false`) against the verified archive.
  It exited 0 and reported **Upload succeeded / EXPORT SUCCEEDED** at
  2026-09-29 04:59:50 UTC. Receipt: `codex-upload.log` in the private artifact
  directory. Version/build remained 1.0.5 (15).
- Safari confirmed build processing, selection of build 15, and submission
  of 1.0.5 with the saved release notes and reviewer instructions. The final
  receipt showed **1 Item Submitted** and **Waiting for Review** at
  2026-09-29 05:03 UTC (12:03 AM America/Chicago).
- Submission ID: `f7fa62af-c203-4262-ba97-a9d191256aea`.
  [App Review receipt](https://appstoreconnect.apple.com/).
  The detail page independently showed `iOS App 1.0.5`, `1.0.5 (15)`,
  `Waiting for Review`, and the submission timestamp. Safari was left there.
- Automatic release after App Review approval is selected, with immediate
  availability to all users once Apple approves. No public-release receipt
  exists yet; the previously verified public version was 1.0.4.

### Coordination and ownership

Claude was the sole application-source writer, configured in its desktop UI
for Opus 5.5, High effort, Bypass permissions (explicitly confirmed by the
owner). Codex controlled Claude/Safari and independently verified the result.
No additional Claude/Codex plugin was needed for the Computer Use route.

| Agent | Bounded responsibility | Requested route | Effective route |
| --- | --- | --- | --- |
| auth_diagnosis | Read-only callback diagnosis and official Supabase source check | Terra High | Unverified |
| release_inventory | Read-only device, version and release-tooling inventory | Luna Medium | Unverified |
| auth_patch_review | Independent code, privacy and final evidence review | Sol High | Unverified |

These lanes supplied independent diagnosis and review while Claude handled
implementation and device runs. No child agents wrote source or ran competing
device builds; no grandchildren were spawned.

Task changes: `AuthService.swift`, `AuthReliabilityTests.swift`,
`BrassTuneAppTests.swift`, new `PhysicalGoogleAuthGateUITests.swift`,
`project.pbxproj`, this note, and `DOCS_INDEX.md`.

## Remaining

- Apple review and public availability remain external pending stages.
  Automatic release is configured; no further manual release click is needed
  after approval under the selected setting.
- The Google flow is proven on this phone for 1.0.5 (15) only. Other devices
  and first-consent flows are unverified.
