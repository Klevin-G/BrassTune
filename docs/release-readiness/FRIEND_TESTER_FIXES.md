# Friend Tester Fixes

Status: implemented locally on `arya/release-readiness-hardening`; hosted behavior must be re-smoked after deployment.

## Reproduced Feedback

- Auth pages exposed provider/configuration language when accounts were unavailable.
- Guest recording could fall into authenticated session calls and show account-required failures.
- Microphone state could imply readiness before the full stream/backend path was usable.
- The local media import UI used camera/video-first language even though BrassTune analyzes audio.
- Dashboard and settings copy included developer-oriented backend/setup wording.

## Product Changes

- Unsigned users can use guest practice without cloud auth. Guest sessions are local to the browser/device.
- Auth-unavailable copy now says accounts are not enabled for this beta build and offers `Continue as guest`.
- Recording in guest mode creates a local reviewable session instead of calling authenticated session endpoints.
- Session review, local export, and guest audio playback use local guest session data when available.
- Media import is now `Import recording` / `Choose audio or video file` and explains the audio track is analyzed.
- Runtime API/WS configuration is centralized; Render fallback is limited to known BrassTune hosts.
- User-facing backend/auth errors are mapped to beta-friendly guest/cloud-sync language.

## Still External

- Real account creation requires Supabase env vars and redirect URLs.
- Hosted microphone/WebSocket behavior must be tested again after Vercel redeploy.
- Apple sign-in, production account deletion, and App Store/device microphone evidence remain external gates.
