# Phone Microphone Test Report

Status: manual real-device testing still required.

Automated Chromium simulation verifies layout and demo recording. It does not prove iPhone/iPad Safari microphone behavior.

## Test URLs

- Frontend: set after Vercel deployment
- Backend health: `https://brasstune.onrender.com/api/health`
- Audio Lab: `/settings/audio-lab`

## Devices

- iPhone Safari: not yet tested
- iPad Safari: not yet tested
- Mac Chrome: not yet tested
- Mac Safari: not yet tested
- Chromebook Chrome: not yet tested

## Instruments

- Trumpet: not yet tested
- Horn: not yet tested
- Trombone: not yet tested
- Euphonium: not yet tested
- Tuba: not yet tested

## Checklist

For each device/instrument/room:

- Sign in or use guest demo.
- Go to Practice.
- Disable demo mode.
- Enable microphone.
- Grant permission.
- Play a 30-second long tone.
- Confirm WebSocket connects.
- Confirm RMS moves.
- Confirm note lock appears.
- Confirm confidence reaches recording-quality lock.
- Confirm no-lock copy is understandable.
- Stop and verify pitch analytics save.
- Verify relisten audio appears.
- Open Session Review and play audio.
- Export ZIP and verify audio is included.

## Native Camera / Local Upload Checklist

- Record a short video in the native Camera app.
- Upload it from Photos/Files in Practice.
- Confirm BrassTune does not upload or store the source video.
- Confirm local browser analysis creates a session.
- Confirm Session Review, Analytics, and Coach use the imported session.
- Use the Practice Camera button and verify iOS opens the native capture picker.

## Data to Record

- Lock time
- False no-lock rate
- Octave jumps
- Low brass detection quality
- 4096-frame perceived latency
- Saved samples per 30 seconds
- Audio playback availability
- Browser sample rate
- Detector source

## Current Risks

- The 95% confidence floor may reject too much real brass audio.
- Safari sample rates and permission behavior need physical-device validation.
- Supabase signed playback depends on bucket and CORS configuration.
- Browser media decode support differs by video container and codec; unsupported videos may need an audio export.
