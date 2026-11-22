# Competitive practice release — October 25, 2026

Project attribution: Kelvin Guo, Arya Salem.

Candidate: 1.0.9 (21), com.aryasalem.BrassTune. Includes the silent-bar trainer and intonation-history changes documented in TONALENERGY_COMPARISON_2026-10-23.md.

Signed archive, App Store export, codesign verification, version/bundle checks and upload passed. Apple reported Upload succeeded / Uploaded package is processing. Safari confirmed 1 Item Submitted, Draft Submissions (0), and 1.0.9 Waiting for Review. The App Store Connect receipt is stored with the owner’s release evidence.

Evidence: ~/Library/Application Support/BrassTune/ReleaseEvidence/CompetitivePractice-2026-10-25/1.0.9-21/.

Prior validation: 378 native unit, 12 core, 4 simulator UI and 2 physical checks passed. The comparison ledger matched 12/12 source files before the version-only bump. Independent audit of the prior 56-file release ledger found 49 unchanged and seven expected comparison/project changes, with no unexpected drift. Requested auditor routing: Luna Medium; effective routing unavailable. Parent owns version metadata, archive/export/upload and Safari submission. No device automation or prompts to Arya’s iPhone were requested in this release turn.

Apple Developer agreement issued October 13, 2026 was accepted October 25, 2026 through Safari after explicit action-time user authorization. Existing App Store 1.0.8 is Ready for Distribution. New version is configured for automatic release after Apple approval, immediately to all users. No claim of public availability for 1.0.9 until verified.

Earlier dirty work was preserved. No Git commit/push, backend or website deployment was performed. New verification ran xcodebuild archive, xcodebuild -exportArchive (export and upload), codesign --verify --deep --strict, metadata/hash checks and an independent provenance audit. Tests were reused because only version metadata changed after the tested implementation. Physical acoustic quality, alternate input routes and universal device behavior remain unverified.
