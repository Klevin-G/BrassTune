# GitHub source update — November 22, 2026
Project attribution: Kelvin Guo, Arya Salem.

This update synchronizes the accumulated native practice/audio/auth improvements,
web and Android source, static marketing site and recovery service, tests, and
release documentation to a review branch. It is not a production deployment,
App Store release, or physical-device certification. GitHub reported the
repository already public during this review. Visibility was not changed.

## Validation

- Backend: `.venv/bin/python -m pytest -q`: 364 passed, 13 skipped.
- Frontend under Homebrew Node 24: `npm test`: 47 files, 295 tests passed;
  `npm run build`: passed. Main bundle size warning remains (651.09 kB).
- Marketing build/checks, recovery bridge checks, and backend recovery JavaScript
  checks passed.
- Swift core: `swift test --scratch-path /tmp/brasstune-core-validation`:
  12 tests passed.
- Native design tokens, localization (1,049 static keys), release-auth configuration
  tests, and unsigned Debug iOS simulator build passed.
- Documentation attribution check passed after adding missing creator credits to
  two historical QA notes.
- No browser E2E, Android Gradle/device tests, native app unit/UI tests, signed
  archive, physical-device validation, hosted checks, or deployment was performed
  in this source synchronization pass.

## Publication boundaries

Private feedback and outreach notes remain local and are intentionally excluded
from this public update. Ignored environment files, recordings, generated builds,
local SDK settings, and credentials are not part of the commit. Historical release
notes describe their own dates; they do not establish current production status.

A public repository is useful for portfolio review and collaboration, but the
owners should explicitly agree on source availability and choose a licensing
policy. No root source-code license was found. Existing third-party credits remain
in `docs/CREDITS.md`. This pass does not certify all historical content or perform
a comprehensive vulnerability audit.

## Independent review

Three bounded agents reviewed publication safety (requested Sol high), web/backend
validation (requested Terra medium), and native validation (requested Terra
medium). Effective routing was not independently observable. The parent integrated
results, handled staging/commit/push, and preserved local private notes.
