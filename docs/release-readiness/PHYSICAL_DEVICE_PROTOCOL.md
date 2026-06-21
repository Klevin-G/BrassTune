# Physical Device Protocol

Simulator and generated audio tests do not prove microphone quality. Run this before App Store release.

## Devices

- Recent supported iPhone on latest iOS.
- Supported iPad on latest iPadOS.

## Environments

- Quiet room.
- Noisy room/rehearsal room.
- Low brass close and normal distance.
- High brass close and normal distance.
- Wired route change if supported.
- Bluetooth route change if supported.

## Required Steps

1. Fresh install.
2. Deny microphone permission and verify denied/retry UI.
3. Allow microphone permission and verify live tuner lock.
4. Record, show visible recording indicator, stop, save.
5. Relisten playback.
6. Delete session and verify recording removal.
7. Background/foreground during recording.
8. Audio interruption during recording.
9. Route change during recording.
10. Export/share session.
11. Sign in, restore session, sign out.
12. Account deletion initiation and local sign-out.

## Pass Criteria

- No hidden recording.
- No retained recording without consent.
- No crash on denial/interruption/route change.
- Pitch state distinguishes no-lock, unstable, sharp, flat, and in-tune.
- Saved session, playback, export, deletion, and cleanup behave as documented.
