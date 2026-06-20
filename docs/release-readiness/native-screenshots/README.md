# Native Screenshot Capture

Do not commit huge screenshot sets. Keep only small representative PNGs when needed for release evidence.

Suggested simulator captures:

- iPhone Home
- iPhone Practice
- iPhone Session Review
- iPhone Settings
- iPad Home or Practice
- Dark mode
- Large Dynamic Type

Example:

```bash
xcrun simctl io <simulator-id> screenshot docs/release-readiness/native-screenshots/iphone-practice.png
```

If screenshots include personal data, keep them out of Git and record only their local evidence path in the release report.
