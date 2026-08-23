# App Review Notes Draft
Project attribution: Kelvin Guo, Arya Salem.

Updated: 2026-08-23. This is prepared copy, not a saved App Store Connect record.

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
  is intended to be stored privately, replaceable/removable, and queued for
  cleanup on account deletion. Backend lifecycle validation and deployment
  evidence are pending. It is not shown to class-report surfaces or used for
  ads or tracking.
- Account deletion is available in app for signed-in accounts. Local guest data
  can be cleared separately.

## Not yet ready to paste as a final submission

- The intended next candidate is source version `1.0.1 (6)`; no archive,
  upload, processed TestFlight install, or final dSYM is documented here.
- No current-source archive, upload, processed TestFlight install, or final dSYM
  has been produced.
- The original audio crash families have strong repaired-source physical
  evidence on the built-in route, including a fresh current-source `7/7`
  targeted device pass, but not against the exact next processed build.
- App Store Connect metadata, privacy (including Name and Photos or Videos for
  the profile feature), age rating, price/availability,
  accessibility labels, content rights, reviewer phone, and DSA trader status
  are not complete.

See [`APP_STORE_SUBMISSION_PACKET_2026-08-05.md`](APP_STORE_SUBMISSION_PACKET_2026-08-05.md)
for complete product-page copy and field-by-field answers.
