# Android execution setup

Assessed October 8, 2026. Codex CLI 0.149.1; repo-codex-bootstrap workflow.

## Architecture and environment

Android is a new, isolated platform lane using the existing React/Vite frontend
and Capacitor 8.5.3. Native Swift code is unaffected. The implementation worktree
was created from the current Git HEAD with the existing dirty frontend baseline
copied before implementation. Preserve unrelated translation/API-test edits.

Installed tooling: Node 24.21.0, Android Studio Rabbit 1 2026.2.1.8,
Android command-line tools 15859902, OpenJDK 21.0.12.1, API 36, build-tools
36.0.0, platform-tools 37.0.1 and Android Emulator 37.2.12. Use task-local
environment variables rather than changing another project's global toolchain:

```sh
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
```

The `medium_phone` ARM64 API 36 AVD was created for this work. Discover its live
serial before tests; never assume `emulator-5554` belongs to this task later.
Android Studio's bundled Java 25 failed the generated Gradle 8.14.3 import;
Java 21 builds successfully. The IDE was configured to use JVM 21.

## Coordination

This is a multi-lane task: Android implementation, independent review/runtime
QA, iOS candidate validation and faculty outreach have separate ownership.
Concurrency is bounded by the supported session cap (nine); depth one is policy.
No legacy `agents.max_threads`, `agents.max_depth` or runtime-limit TOML keys
were added, and no new permanent agent profiles were necessary.

Requested routes: Terra High for Android integration; Sol High for independent
native/React lifecycle review and instrumentation; Terra Medium for iOS
artifact/device work; Luna Medium for bounded source research. Outreach/audit
completion escalated to Sol Medium after evidence persistence repeatedly fell
behind external actions. Effective child routing was not independently visible.

Use separate worktrees for independent platform writers. Within Android, keep
the application writer separate from the instrumentation writer; coordinate
`app/build.gradle` ownership and serialize actual emulator interaction.
Atomic docs/config corrections do not need fanout. Repeated independent public
source audits can use bounded batch lanes with durable receipts.

## Definition of done and known gates

Shared frontend tests/build, Capacitor sync, native build/lint, meaningful native
tests and packaged-app runtime checks must have receipts. Keep guest-only alpha,
authenticated app, emulator validation, physical audio QA, signed upload and
public availability distinct. Cloud/account functionality cannot be inferred
from a successful guest APK. Use `android.md` for current commands and platform
limitations; record final test/artifact results in the release-readiness report.

Google Play setup was inspected but no developer account was created. The
BrassTune Google account first needs 2-step verification and a confirmed legal
publisher. A new personal account may require identity/device verification and
a qualifying closed test before production access. Account setup is currently
on hold at the user's request while choosing the publishing identity.
