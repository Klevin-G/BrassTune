# Google sign-in follow-up — October 6, 2026

> October 8 continuation: a signed 1.0.6 (16) candidate containing this patch
> was installed in place. New physical tests were blocked by the locked phone;
> no Apple upload occurred during this follow-up.

Project attribution: Kelvin Guo, Arya Salem.

## Status and scope

The recurring production callback error remains under investigation. A separate
callback compatibility defect has been reproduced and patched locally: a valid
PKCE callback with a trailing empty `#` was rejected. This is not yet proof of
the cause of the user's reported failed attempts. No production configuration,
credential, OAuth client, release, or App Store submission has been changed.

The supplied `BrassTune To-do.pdf`, pages 4–5, describes this as the highest
priority 1.0.5 problem. Its other critiques concern instrument selection,
tuner whitespace, Practice/Scales/Progress clarity, performance, offline saving,
and possible Watch/iPad work. Those were reviewed and mapped to source; they
are not claimed as implemented by this auth change.

## Live configuration and existing artifact

- Apple's public US lookup reports version 1.0.5, released
  `2026-09-29T18:13:42Z`.
- The connected iPhone's production bundle is `com.aryasalem.BrassTune`
  1.0.5 (15); the separate development app is 1.0.4 (14).
- Google Cloud project `brasstune` is External / In production. Its enabled
  Web OAuth client redirects to the expected Supabase HTTPS auth callback.
- Claude's read-only live check found GoTrue v2.197.0, Google enabled, and the
  production/development custom-scheme redirect allowlist unchanged.
- No evidence justified resetting Google Cloud clients or credentials.

## Production baseline on the connected phone

The existing opt-in `PhysicalGoogleAuthGateUITests` drove the installed
production bundle, without reinstalling or resetting it. The development UI
test runner is separate from that production install.

Passed: activation; sign-out and signed-out cold launch; real Google sign-in;
signed-in cold restore; system-prompt cancellation followed by successful retry;
final cold restore. One cancellation test initially failed its signed-out
precondition; after an explicit sign-out it passed. That harness ordering error
is not an OAuth callback failure.

No UIXcodeAutomation password prompt appeared. The existing authorization was
sufficient for these tests. This does not guarantee macOS will never request
authorization again. Only the already-known Google account was exercised;
password/MFA and first-time consent were not covered by automation.

## Unresolved production observations

Claude's sanitized live traces show production build-15 callbacks at October 7
01:50:06–07 and 02:33:44 UTC (October 6 20:50 and 21:33 CDT), with no following
PKCE exchange in the inspected trace. Our 02:42:40 and 02:45:20 UTC attempts did
exchange successfully. OS/build/account markers do not uniquely identify a
physical phone; timing correlation is not proof of device identity or causation.

The owner collected a private device log archive. It spans 18:48–21:48 CDT,
but its BrassTuneApp records and production launch records begin at 21:40:57,
matching our automation. It contains no callback-rejection diagnostic or app
launch at the earlier failure windows. Therefore it cannot settle the root
cause. A live production console capture was prepared for a manual retry.

## Reproduced defect and bounded change

A standalone local WebKit fixture with fake values reproduces fragment
inheritance through two HTTP 302 redirects into a custom-scheme callback.
Foundation represents a bare trailing `#` as an empty, non-nil fragment. The
previous `fragment == nil` guard rejected that otherwise valid callback.

The success branch now permits only an absent or exactly empty fragment.
Nonempty fragments still fail closed, including punctuation-only fragments,
second hash markers and encoded control characters. Scheme, host, path,
authority, exact state, exact query field counts, code validation and S256 PKCE
binding are preserved. A raw-fragment check complements Foundation parsing.

The diagnostic adds a value-free `fragment_empty` boolean. Zero parsed fragment
fields alone is not evidence of emptiness. No callback values or arbitrary
callback-supplied field names are logged.

## Completed local verification

The final auth subset passed **22/22** and the full native unit suite passed
**329/329**, on iPhone 17 Pro Simulator / iOS 26.5. A mutation check restored
the old guard and made exactly the two new positive empty-fragment tests fail
(12 tests, 2 expected failures), then restored the fix. All 24 nonempty-fragment
fixtures also run through service-level zero-request/no-credential assertions.

The independent reviewer verified the saved logs, result bundles, added
second-hash/control cases, and the frozen SHA-256 values:

- `AuthService.swift`: `7682dc06670bfea14556f6e6aea77c49eca7ce33a2898152b1893f2be687105b`
- `AuthReliabilityTests.swift`: `159f2c097afddf490bd064fbdc808dd549945accf6717de57ae7735ac6ad36ce`

Evidence is under the private local directory
`~/Library/Application Support/BrassTune/ReleaseEvidence/GoogleAuthCallback-fragment-2026-10-06/`:
`oct-unit-auth.log`, `oct-unit-full.log`, `oct-mutation.log`, matching result
bundles, and isolated source diffs. Version/build remain 1.0.5 (15); this modified
source has not replaced the production app or been uploaded. The existing-phone
passes above are baseline evidence, not physical validation of the new patch.
Web/backend, shared Swift package, broader audio, and UI suites were not rerun
because this change is confined to the native callback validator and its tests.
Both release-auth preflight scripts and `git diff --check` also passed.

## Coordination and artifacts

Claude Desktop was visibly configured for Opus 5.5 / High. Claude owns the two
auth source/test files; Codex coordinates and independently reviews evidence.
No child model routing was independently observable from runtime metadata.

The inspected `davidq888/claude-code-codex-plugin` bridge was installed locally
at `~/plugins/claude-code`, pinned to source commit
`fe2b3ed53a61863ef0bbb5938b8a2b406a205476`. Its direct smoke test reached Claude
CLI but returned `Not logged in`; it is not an authenticated integration in this
chat. The authorized Claude Desktop fallback was used throughout instead.
The installer registered the bridge in the Personal marketplace for a new
Codex task; no unrelated application permissions were changed.

| Lane | Requested route | Responsibility |
|---|---|---|
| Native scout | Terra High | Read-only callback diagnosis and critique/source map |
| Device gate | Terra Medium | Installed artifact, ordered phone tests, private log analysis |
| Cloud audit | Terra Medium | Google configuration and primary-source verification |
| Critique/research | Luna Medium | PDF extraction and bounded plugin/faculty research |
| Independent auth review | Sol High | Isolated auth diff, security binding and test coverage |
| Outreach coordinator | Terra Medium | Sender/deduplication, personalized mail, send receipts |
| US faculty research | Luna Medium | Public professional contact sources |

Source baseline copies live outside Git under `/tmp/brasstune-oct6-before/`.
Device archives, console captures, result bundles, contact manifests and email
receipts are private local artifacts, not repository deliverables. Existing
unrelated dirty changes are preserved. No Git commit or push has been made.

References: [RFC 9110 Location semantics](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.2),
[Supabase Google login](https://supabase.com/docs/guides/auth/social-login/auth-google),
[Apple callback API](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback).
