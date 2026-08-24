# App Review Notes Draft
Project attribution: Kelvin Guo, Arya Salem.

Updated for the local Classes MVP. Version `1.0.1` is currently **Developer
Rejected / Removed** in App Store Connect, with build 7 still associated. This
is a draft for a future build 8; no archive, upload, build selection, or review
submission is claimed.

## Draft build-8 Classes review path

> Classes are optional and can be reviewed after creating or signing into an
> account. A student may join and consent to the class-sharing flow. Owners can
> use roster, invite, and aggregate participation views; assistants only see
> the delegated role-scoped information. Classes do not provide assignments or
> grades, and do not expose recordings, raw audio, reflection text, score
> content, note events, or individual session detail. Aggregate timing/pitch
> progress is shared only after consent; legacy members are prompted to
> re-consent.

Before this text can be used, apply and verify the migration in the authorized
environment, complete disposable live consent/class acceptance, archive and
upload build 8, wait for processing, select it for `1.0.1`, and submit again.
The project is configured for that candidate as `1.0.1 (8)`, but no archive,
upload, selection, or submission exists. A physical Classes fixture UI run
passed student/owner/assistant workspaces `1/1`, zero failed/skipped, on
Nandy’s iPhone 15 Pro Max / iOS 26.6.1. It does not establish live hosted
multi-account sync or release-candidate behavior.

## Reviewer access

- Sign-in is not required. Core practice is available through guest mode.
- Do not provide a real student's credentials or data.
- Review contact: Arya Salem, `brasstune1@gmail.com`.
- A monitored review phone number remains owner-supplied and must not be
  invented.

## Suggested reviewer notes

> BrassTune can be reviewed without an account. On first launch choose Continue
> as Guest, select any instrument, and choose Start Practicing. The microphone is
> requested only after starting Tuner or a microphone-assisted scale. Scales also
> provide a Visual timing mode that does not require microphone access. Practice
> includes guided warm-ups, metronome, drone and interval tools, reference tones,
> and local score practice. To test a score, import a PDF from Files or an image
> from Photos; add practice notes and select Start guided practice. Imported
> scores and native recordings remain on the device unless the reviewer
> explicitly exports or shares them. Account creation, Apple sign-in, and Google
> sign-in are optional and are not required to exercise the core app.

> To review the optional account-profile flow, create an account, complete the
> required username/display-name fields, then select an optional profile photo
> through the system picker and save. The profile photo is sent only when saved,
> stored privately for that account, and can be replaced or removed in the
> profile editor. This flow is not required for the guest review path.

## Permission and data explanations

- Microphone permission is used for live pitch detection during Tuner and
  microphone-assisted Scale practice.
- Files/Photos access is user-initiated for importing a local score.
- Raw microphone audio is not uploaded by the native app. Local score files and
  native recordings leave the device only through an explicit export/share action.
- An optional profile photo is used only for the signed-in account profile. It
  is stored privately, replaceable/removable, and queued for cleanup on account
  deletion. It is not shown to class-report surfaces or used for ads or tracking.
- Account deletion is available in app for signed-in accounts. Local guest data
  can be cleared separately.

## Submitted-candidate boundary

- Candidate `1.0.1 (7)` was archived/exported from `d371100`, uploaded, and is
  TestFlight **Ready to Submit**. Its IPA has a strict valid distribution
  signature, matching app/dSYM UUID `77D84475-6D50-3D94-B842-290431F0D74D`, and
  SHA-256 `640511f5a15f579500f86710393a6f661ced4cff87a64f00b8ccbe689bea2782`.
- Version `1.0.1` build 7 is submitted and **Waiting for Review** with manual
  release selected. This is not approval or release evidence.
- Automated physical runs cover the listed UI/audio matrices, but calibrated
  acoustic accuracy, accessory routes, Files/Photos fixtures, timer/media-reset
  prerequisites, and full assistive-technology/iPad validation remain unavailable.

See [`APP_STORE_SUBMISSION_PACKET_2026-08-05.md`](APP_STORE_SUBMISSION_PACKET_2026-08-05.md)
for complete product-page copy and field-by-field answers.
