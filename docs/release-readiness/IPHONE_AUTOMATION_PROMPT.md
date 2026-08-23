# Physical iPhone Automation Prompt
Project attribution: Kelvin Guo, Arya Salem.

Use this reusable prompt for an attended, USB-connected device pass:

> Using the USB-connected iPhone, build and install the current BrassTune iOS app from this repository, run every available unit, integration, and XCUITest on the physical device, then perform an attended end-to-end device QA pass covering account creation, login/logout, guest-session cleanup after app termination/relaunch, onboarding/tutorial, profile username/photo, always-on tuner and optional recording, metronome first-play audio/visual synchronization/tempo changes/compound meters, drone audio, navigation, button visibility, support/privacy/credits, accessibility, interruptions, background/foreground, rotation, and relaunch persistence. Capture exact build/device/OS/SHA evidence, screenshots or logs for failures, and distinguish automated, simulator-only, and physically observed results. Do not claim microphone/audio quality or App Store readiness without physical evidence. Fix reproducible in-scope defects, rerun the affected tests, then report remaining blockers before any submission.

## Evidence boundary

- **Automated:** record the command or test plan, result, revision, and whether the test actually targeted the connected device. Automation exercises scripted scope; it is not a blanket usability, audio-quality, or App Store conclusion.
- **Simulator-only:** identify the simulator model and OS. It is not physical-device evidence for microphones, audio routes, interruptions, assistive technology, signing, or App Store readiness.
- **Physically observed:** record the connected device model, OS, installed build, source SHA, observer, and failure artifacts. Only this category can support a physical microphone or route observation, and it still does not itself establish App Store acceptance.

Keep missing evidence as unknown. Re-run only the affected automated checks after an in-scope repair; preserve failures and external/provider gates for the final handoff.
