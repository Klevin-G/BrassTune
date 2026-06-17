# Manual Test Plan

## New User

1. Open the app on phone width.
2. Confirm onboarding appears on first local visit.
3. Choose instrument.
4. Confirm A4 reference.
5. Choose demo or microphone mode.
6. Read No lock vs unstable pitch.
7. Start a 30-second take.
8. Stop and confirm session review opens.

## Auth

1. Go to `/auth/sign-up`.
2. Create an account with email, password, username, display name, and instrument.
3. Confirm email if Supabase requires it.
4. Sign in.
5. Confirm More/Settings show username.
6. Sign out.
7. Sign in again.
8. Confirm onboarding does not reappear unless reopened.

## Practice and Audio

1. Record demo session.
2. Confirm synthetic audio playback appears.
3. Disable demo mode.
4. Enable microphone.
5. Record mic session.
6. Confirm analytics save even if audio upload fails.
7. Confirm Session Review plays audio when available.

## Local Video/Audio Import

1. Record a short brass video with the native phone Camera app.
2. Open Practice.
3. Use Choose file to select the video from Photos/Files.
4. Confirm the app says the source media is not uploaded or stored.
5. Wait for local analysis.
6. Confirm a session is created with note analytics.
7. Use Camera on iPhone/iPad and confirm the native camera picker opens.
8. Confirm unsupported video containers show a friendly decode error.

## Exports

1. Open Sessions.
2. Use export menu.
3. Download samples CSV, note events CSV, JSON, ZIP, and audio.
4. Confirm ZIP includes README and audio when available.

## Analytics and Coach

1. Open Analytics.
2. Change period filter.
3. Select heat map note.
4. Confirm selected note inspector updates without layout overflow.
5. Open Coach and confirm recommendations render.

## Ensemble

1. Sign in as director/admin.
2. Create a group.
3. Add a student by username.
4. Confirm unknown username error.
5. Confirm student cannot add members.
6. Open section trends and rehearsal report.
7. Print/export report.

## Deployment Phone Test

1. Open Vercel URL on iPhone Safari.
2. Open Audio Lab.
3. Confirm backend and WebSocket URLs.
4. Grant mic permission.
5. Play long tone.
6. Record diagnostics in `docs/phone-microphone-test-report.md`.

## Security Checks

1. Try private endpoints without token in `APP_ENV=production`.
2. Try another user’s session with `Bearer dev-user-2` in local test mode.
3. Try bad audio MIME upload.
4. Try oversized audio upload.
5. Run CI/security workflow locally where tools are available.
