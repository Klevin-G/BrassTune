# iOS 1.0.6 (17) artifact verification — October 8, 2026

Project attribution: Kelvin Guo, Arya Salem.

## Release identity

- Bundle identifier: `com.aryasalem.BrassTune`
- Marketing version/build: `1.0.6 (17)`
- Frozen source fingerprints:
  - `swift/BrassTuneApp/BrassTuneApp/AppRootView.swift`: `b7b4b7a3a2b5a4347f365bae40c84c0843c6d58afd8912a72bab8ef86caf09c6`
  - `swift/BrassTuneApp/BrassTuneApp.xcodeproj/project.pbxproj`: `06a13745f9811837ffecca4df2b4744c69fc632ef9ec0b6233ead54ce8cd9d57`
  - `swift/BrassTuneApp/BrassTuneApp/AuthService.swift`: `7682dc06670bfea14556f6e6aea77c49eca7ce33a2898152b1893f2be687105b`
  - `swift/BrassTuneApp/BrassTuneAppTests/AuthReliabilityTests.swift`: `159f2c097afddf490bd064fbdc808dd549945accf6717de57ae7735ac6ad36ce`
- `git diff --check` passed for the frozen native release paths.

## Automated verification

Independent simulator evidence on the frozen source:

- Native unit suite: `332/332` passed.
- Targeted UI: score search and manual sparse-note coverage: `2/2` passed on BrassTune App Store 6.9 Simulator / iOS 26.5.

The simulator logs and result bundles are private under:

`~/Library/Application Support/BrassTune/ReleaseEvidence/Release-1.0.6-17-2026-10-08/simulator/`

## Archive and export

The release script completed its release-auth preflight, then ran:

```text
scripts/ios/build-testflight.sh
```

with the production bundle/team configuration and a private release-evidence output directory. Xcode archive and App Store Connect export both succeeded.

- Archive: `~/Library/Application Support/BrassTune/ReleaseEvidence/Release-1.0.6-17-2026-10-08/archive/BrassTuneApp.xcarchive`
- Exported IPA: `~/Library/Application Support/BrassTune/ReleaseEvidence/Release-1.0.6-17-2026-10-08/archive/export/BrassTuneApp.ipa`
- IPA SHA-256: `5ca5e131a187019e3975e2014ad86081652a3757d50919fb9642ae6fa69918be`

The archive's build-time application signing identity is Apple Development. The exported IPA was independently inspected and is the distribution artifact:

- Identifier: `com.aryasalem.BrassTune`
- Version/build: `1.0.6 (17)`
- Signing authority: Apple Distribution, team `8S79RLTSWV`
- Embedded App Store profile: `get-task-allow=false`, `beta-reports-active=true`, expiry `2027-08-03T23:42:27Z`

## App Store Connect upload

An initial `altool` provider query had no configured CLI JWT or app-password authentication, so no `altool` upload was attempted. The official Xcode path then used the signed-in Xcode account:

```text
xcodebuild -exportArchive \
  -archivePath <BrassTuneApp.xcarchive> \
  -exportOptionsPlist <ExportOptionsUpload.plist destination=upload> \
  -exportPath <upload-result> \
  -allowProvisioningUpdates
```

The private Xcode upload log records `Starting upload`, `Uploaded package is processing`, `Upload succeeded`, and `Uploaded BrassTuneApp`. The log SHA-256 is `3ebe57c53cb3aaa02ffdff6a0cf78033935c8186800fde1193a6f01449f03107`; the copied Xcode distribution logs are preserved beside it.

This proves that build 17 was accepted for App Store Connect processing. It does not prove processing completion, TestFlight availability, selection for the 1.0.6 version, App Review submission, approval, or public App Store release.

## Remaining physical-device boundary

The installed 1.0.6 (16) pre-release phone candidate was blocked from the existing physical UI harness because iPhone 15 Pro Max was locked. No physical run exists for the final 1.0.6 (17) distribution artifact. The earlier known-account production lifecycle evidence exercised build 15 only; it does not validate this build's empty-fragment callback repair, first-consent behavior, password/MFA paths, physical microphone quality, or TestFlight thinning.

Continue App Store Connect processing/selection and any subsequent submission in the owner-controlled portal lane. Keep the private archive, IPA, upload receipt, dSYM, and distribution logs out of Git.
