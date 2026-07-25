import { Buffer } from 'node:buffer';
import { expect, test } from 'playwright/test';
import type { Locator, Page, Route } from 'playwright/test';

const signedInAuthModule = `
const session = { access_token: 'audio-lifecycle-token', user: { id: 'audio-lifecycle-user' } };
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    getSession: async () => ({ data: { session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({ error: null }),
  },
};
`;

const stablePitchStreamModule = `
const stream = { getTracks: () => [{ stop() {} }] };
export function usePitchStream() {
  return {
    currentFrame: null,
    history: [],
    statusMessage: 'Listening. Play a steady note.',
    micActive: true,
    mediaStream: stream,
    streamInfo: {},
    startMicrophone: async () => stream,
    stopMicrophone() {},
    flushPendingFrames: async () => ({ flushed: 0, failed: 0 }),
    finishPersistingFrames: async () => ({ flushed: 0, failed: 0 }),
  };
}
`;

const activeSession = {
  id: 701,
  user_id: 91,
  instrument_id: 'trumpet',
  name: 'Lifecycle take',
  started_at: '2026-07-23T12:00:00.000Z',
  ended_at: null,
  created_at: '2026-07-23T12:00:00.000Z',
  duration_seconds: 0,
  reference_pitch_hz: 440,
  notes_count: 0,
  average_signed_cents: 0,
  average_abs_cents: 0,
  in_tune_percentage: 0,
  audio_available: false,
};

async function installTunerRecordingFixture(page: Page, options: { failFirstStop?: boolean; pendingStart?: boolean } = {}) {
  const calls = { starts: 0, uploads: 0, stops: 0 };
  let resolveStart: (() => void) | undefined;
  const startGate = options.pendingStart
    ? new Promise<void>((resolve) => { resolveStart = resolve; })
    : Promise.resolve();

  await page.addInitScript(() => {
    const state = { starts: 0, stops: 0 };
    class FakeMediaRecorder {
      static isTypeSupported() { return true; }
      mimeType = 'audio/webm';
      ondataavailable: ((event: { data: Blob }) => void) | null = null;
      onstop: (() => void) | null = null;
      constructor(_stream: MediaStream, _options?: MediaRecorderOptions) {}
      start() {
        state.starts += 1;
      }
      stop() {
        state.stops += 1;
        this.ondataavailable?.({ data: new Blob(['recorded audio'], { type: this.mimeType }) });
        this.onstop?.();
      }
    }
    Object.defineProperty(window, 'MediaRecorder', { configurable: true, value: FakeMediaRecorder });
    (window as unknown as { __tunerRecorderTest: unknown }).__tunerRecorderTest = state;
  });
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: signedInAuthModule,
  }));
  await page.route('**/src/hooks/usePitchStream.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: stablePitchStreamModule,
  }));
  await page.route(/^https?:\/\/[^/]+\/api\//, async (route: Route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const json = (body: unknown, status = 200) => route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify(body),
    });

    if (path === '/api/instruments') return json([]);
    if (path === '/api/users/current') {
      return json({
        id: 91,
        supabase_user_id: 'audio-lifecycle-user',
        username: 'audio-lifecycle',
        display_name: 'Audio Lifecycle',
        email: 'audio@example.test',
        role: 'student',
        primary_instrument_id: 'trumpet',
        onboarding_completed_at: '2026-07-23T10:00:00.000Z',
      });
    }
    if (path === '/api/sessions/start' && request.method() === 'POST') {
      calls.starts += 1;
      await startGate;
      return json(activeSession);
    }
    if (path === `/api/sessions/${activeSession.id}/audio` && request.method() === 'POST') {
      calls.uploads += 1;
      return json({
        uploaded: true,
        audio: { ...activeSession, audio_available: true, audio_mime_type: 'audio/webm' },
      });
    }
    if (path === `/api/sessions/${activeSession.id}/stop` && request.method() === 'POST') {
      calls.stops += 1;
      if (options.failFirstStop && calls.stops === 1) {
        return json({ detail: 'Temporary stop failure' }, 503);
      }
      return json({
        ...activeSession,
        ended_at: '2026-07-23T12:00:04.000Z',
        duration_seconds: 4,
        audio_available: true,
      });
    }
    return json({ detail: 'Not found' }, 404);
  });

  return {
    calls,
    releaseStart: () => resolveStart?.(),
  };
}

async function savedWeeklyCompletion(page: Page, ownerKey = 'account%3A91') {
  return page.evaluate((key) => {
    const raw = localStorage.getItem(`brasstune.practiceLibrary.v1.${key}`);
    const weeklyGoal = raw ? JSON.parse(raw).weeklyGoal : null;
    return weeklyGoal
      ? { minutes: weeklyGoal.completedMinutes, sessions: weeklyGoal.completedSessions }
      : { minutes: 0, sessions: 0 };
  }, ownerKey);
}

function appShellLink(page: Page, name: string): Locator {
  return page.locator('.sidebar:visible, .floating-tabbar:visible').getByRole('link', { name, exact: true });
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .forEach((key) => localStorage.removeItem(key));
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
});

test('a centered low-confidence frame never renders or announces an in-tune reward', async ({ page }) => {
  await page.route('**/src/hooks/usePitchStream.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: `
const frame = {
  timestamp_ms: 1, frequency_hz: 440, confidence: 0.94, rms: 0.1,
  midi_note_float: 69, nearest_midi: 69, concert_note_name: 'A', concert_octave: 4,
  written_note_name: 'B', written_octave: 4, cents_deviation: 0, tuning_status: 'unstable',
  instrument_id: 'trumpet', reference_pitch_hz: 440, is_valid_for_recording: false,
  save_eligibility_reason: 'confidence below 95%'
};
export function usePitchStream() {
  return {
    currentFrame: frame, micActive: false, mediaStream: null, statusMessage: '',
    startMicrophone: async () => null, stopMicrophone() {}, captureFrame() {},
    finishPersistingFrames: async () => ({ saved: 0, rejected: 0, failed: 0 })
  };
}
`,
  }));

  await page.goto('/practice');
  const note = page.locator('.note-display');
  await expect(note).toHaveAttribute('aria-label', 'Play a note');
  await expect(note.locator('.note-display-verdict')).toHaveText('Play a note');
  await expect(note).not.toHaveClass(/tone-green/);
  await expect(page.locator('.tuning-meter')).toHaveAttribute('aria-valuetext', 'No note');
  await expect(page.locator('.tuning-meter-reward')).toHaveCount(0);
  await expect(note.locator('[aria-live="polite"]')).not.toContainText('In tune');
});

test('switching to Demo cancels a microphone grant that resolves later', async ({ page }) => {
  await page.addInitScript(() => {
    let resolveRequest: ((stream: unknown) => void) | undefined;
    const pending = new Promise((resolve) => { resolveRequest = resolve; });
    const state = { requests: 0, stopped: 0 };
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: () => {
          state.requests += 1;
          return pending;
        },
      },
    });
    (window as unknown as { __micTest: unknown }).__micTest = {
      state,
      resolve: () => resolveRequest?.({ getTracks: () => [{ stop: () => { state.stopped += 1; } }] }),
    };
  });

  await page.goto('/practice');
  await expect.poll(() => page.evaluate(() => (window as unknown as { __micTest: { state: { requests: number } } }).__micTest.state.requests)).toBe(1);
  await page.getByRole('radio', { name: 'Demo', exact: true }).click();
  await page.evaluate(() => (window as unknown as { __micTest: { resolve: () => void } }).__micTest.resolve());

  await expect.poll(() => page.evaluate(() => (window as unknown as { __micTest: { state: { stopped: number } } }).__micTest.state.stopped)).toBe(1);
  await expect(page.getByRole('button', { name: 'Turn on microphone' })).toHaveCount(0);
});

test('a user can retry and resume an AudioContext after automatic startup is unavailable', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { requests: 0, contexts: 0, resumeCalls: 0 };
    class FakeAudioContext {
      state: AudioContextState = 'suspended';
      sampleRate = 48_000;
      destination = {};
      constructor() { state.contexts += 1; }
      resume() {
        state.resumeCalls += 1;
        if (state.resumeCalls === 1) return Promise.reject(new Error('User gesture required'));
        this.state = 'running';
        return Promise.resolve();
      }
      close() {
        this.state = 'closed';
        return Promise.resolve();
      }
      createMediaStreamSource() { return { connect: () => undefined, disconnect: () => undefined }; }
      createScriptProcessor() { return { connect: () => undefined, disconnect: () => undefined, onaudioprocess: null }; }
      createGain() { return { gain: { value: 1 }, connect: () => undefined, disconnect: () => undefined }; }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: async () => { state.requests += 1; return { getTracks: () => [{ stop: () => undefined }] }; } },
    });
    (window as unknown as { __audioContextTest: unknown }).__audioContextTest = state;
  });

  await page.goto('/practice');
  await expect.poll(() => page.evaluate(() => (window as unknown as { __audioContextTest: { requests: number } }).__audioContextTest.requests)).toBe(1);
  const turnOnMic = page.getByRole('button', { name: 'Turn on microphone' });
  await expect(turnOnMic).toBeVisible();
  // React StrictMode cancels the development-only first mount request. The
  // first explicit tap creates the stable context; its simulated autoplay
  // rejection leaves the same button available for one more resume attempt.
  await turnOnMic.click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __audioContextTest: { requests: number } }).__audioContextTest.requests)).toBe(2);
  await expect.poll(() => page.evaluate(() => (window as unknown as { __audioContextTest: { contexts: number } }).__audioContextTest.contexts)).toBe(1);
  await expect.poll(() => page.evaluate(() => (window as unknown as { __audioContextTest: { resumeCalls: number } }).__audioContextTest.resumeCalls)).toBe(1);
  await expect(turnOnMic).toBeVisible();
  await turnOnMic.click();

  await expect.poll(() => page.evaluate(() => (window as unknown as { __audioContextTest: { resumeCalls: number } }).__audioContextTest.resumeCalls)).toBe(2);
  await expect(turnOnMic).toHaveCount(0);
});

test('idle Tuner switches to Drone immediately', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('brasstune.demoMode', 'true'));
  await page.goto('/practice');

  await page.getByRole('radio', { name: 'Drone / intervals' }).click();

  await expect(page).toHaveURL(/tool=drone/);
  await expect(page.getByRole('heading', { name: 'Drone and interval tone' })).toBeVisible();
});

test('Tuner finalizes one active MediaRecorder and cloud session before repeated Drone requests can hide controls', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page);
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();

  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await expect.poll(() => fixture.calls.starts).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { starts: number } }
  ).__tunerRecorderTest.starts)).toBe(1);

  const drone = page.getByRole('radio', { name: 'Drone / intervals' });
  await drone.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });

  await expect(page).toHaveURL(/tool=drone/);
  await expect(page.getByRole('heading', { name: 'Drone and interval tone' })).toBeVisible();
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { stops: number } }
  ).__tunerRecorderTest.stops)).toBe(1);
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
});

test('leaving the Tuner route finalizes one active recorder and cloud session', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page);
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await page.getByRole('link', { name: 'Metronome' }).click();

  await expect(page).toHaveURL(/\/metronome$/);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { stops: number } }
  ).__tunerRecorderTest.stops)).toBe(1);
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
});

test('leaving the Tuner route waits for a pending start and then finalizes it', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { pendingStart: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect.poll(() => fixture.calls.starts).toBe(1);

  await page.getByRole('link', { name: 'Metronome' }).click();
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByRole('button', { name: 'Starting your take' })).toBeVisible();
  expect(fixture.calls.stops).toBe(0);

  fixture.releaseStart();

  await expect(page).toHaveURL(/\/metronome$/);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { starts: number; stops: number } }
  ).__tunerRecorderTest)).toEqual({ starts: 1, stops: 1 });
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
});

test('a failed active Tuner stop keeps an AppShell navigation on Tuner until the player retries', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { failFirstStop: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await appShellLink(page, 'Progress').click();

  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Cloud practice is unavailable');
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 0, sessions: 0 });

  await appShellLink(page, 'Progress').click();

  await expect(page).toHaveURL(/\/progress$/);
  await expect.poll(() => fixture.calls.stops).toBe(2);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
});

test('clicking the already-active Tuner navigation never finalizes an active take', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page);
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await appShellLink(page, 'Tuner').click();
  await page.waitForTimeout(150);

  expect(fixture.calls.stops).toBe(0);
  expect(fixture.calls.uploads).toBe(0);
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await page.getByRole('button', { name: 'Stop and save' }).click();
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
});

test('a failed pending Tuner stop keeps an AppShell navigation on Tuner until the player retries', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { failFirstStop: true, pendingStart: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect.poll(() => fixture.calls.starts).toBe(1);

  await appShellLink(page, 'Progress').click();
  await expect(page).toHaveURL(/\/practice$/);
  fixture.releaseStart();

  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Cloud practice is unavailable');
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 0, sessions: 0 });

  await appShellLink(page, 'Progress').click();

  await expect(page).toHaveURL(/\/progress$/);
  await expect.poll(() => fixture.calls.stops).toBe(2);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
});

test('competing AppShell links commit only the first destination after a pending Tuner stop', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { pendingStart: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect.poll(() => fixture.calls.starts).toBe(1);

  await appShellLink(page, 'Progress').evaluate((link) => (link as HTMLAnchorElement).click());
  await page.getByRole('link', { name: 'Metronome' }).evaluate((link) => (link as HTMLAnchorElement).click());
  await expect(page).toHaveURL(/\/practice$/);
  fixture.releaseStart();

  await expect(page).toHaveURL(/\/progress$/);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await page.goBack();
  await expect(page).toHaveURL(/\/practice$/);
  await page.goForward();
  await expect(page).toHaveURL(/\/progress$/);
});

test('browser Back waits for an active Tuner take to stop before leaving the route', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page);
  await page.goto('/progress');
  await appShellLink(page, 'Tuner').click();
  await expect(page).toHaveURL(/\/practice$/);
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await page.goBack();

  await expect(page).toHaveURL(/\/progress$/);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
});

test('a failed browser Back stop restores the Tuner retry surface before a later Back succeeds', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { failFirstStop: true });
  await page.goto('/progress');
  await appShellLink(page, 'Tuner').click();
  await expect(page).toHaveURL(/\/practice$/);
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await page.goBack();

  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Cloud practice is unavailable');

  await page.goBack();

  await expect(page).toHaveURL(/\/progress$/);
  await expect.poll(() => fixture.calls.stops).toBe(2);
});

test('Drone waits for a pending Tuner start and serializes rapid switch attempts through one finalization', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { pendingStart: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect.poll(() => fixture.calls.starts).toBe(1);

  const drone = page.getByRole('radio', { name: 'Drone / intervals' });
  await drone.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });
  await expect(page).not.toHaveURL(/tool=drone/);
  await expect(page.getByRole('button', { name: 'Starting your take' })).toBeVisible();

  fixture.releaseStart();

  await expect(page).toHaveURL(/tool=drone/);
  await expect(page.getByRole('heading', { name: 'Drone and interval tone' })).toBeVisible();
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { starts: number; stops: number } }
  ).__tunerRecorderTest)).toEqual({ starts: 1, stops: 1 });
});

test('a failed Drone finalization keeps the Tuner stop control available for a successful retry', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page, { failFirstStop: true });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();

  await page.getByRole('radio', { name: 'Drone / intervals' }).click();

  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect(page).not.toHaveURL(/tool=drone/);
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await expect(page.getByRole('alert')).toContainText('Cloud practice is unavailable');
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 0, sessions: 0 });

  await page.getByRole('radio', { name: 'Drone / intervals' }).click();

  await expect(page).toHaveURL(/tool=drone/);
  await expect(page.getByRole('heading', { name: 'Drone and interval tone' })).toBeVisible();
  await expect.poll(() => fixture.calls.stops).toBe(2);
  await expect.poll(() => fixture.calls.uploads).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __tunerRecorderTest: { stops: number } }
  ).__tunerRecorderTest.stops)).toBe(1);
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
});

test('Tuner accounts a successfully saved take exactly once after a focus refresh', async ({ page }) => {
  const fixture = await installTunerRecordingFixture(page);
  await page.goto('/practice');

  await page.getByRole('button', { name: 'Save this take' }).click();
  await expect(page.getByRole('button', { name: 'Stop and save' })).toBeVisible();
  await page.getByRole('button', { name: 'Stop and save' }).click();

  await expect.poll(() => fixture.calls.stops).toBe(1);
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
  await page.evaluate(() => window.dispatchEvent(new Event('focus')));
  await expect.poll(() => savedWeeklyCompletion(page)).toEqual({ minutes: 1, sessions: 1 });
});

test('Play-Along serializes repeated Start activation while permission is pending', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { requests: 0 };
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: () => {
          state.requests += 1;
          return new Promise(() => undefined);
        },
      },
    });
    (window as unknown as { __playAlongMicTest: unknown }).__playAlongMicTest = state;
  });

  await page.goto('/practice/scorer');
  const start = page.getByRole('button', { name: 'Start', exact: true });
  await start.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });

  await expect.poll(() => page.evaluate(() => (window as unknown as { __playAlongMicTest: { requests: number } }).__playAlongMicTest.requests)).toBe(1);
  await expect(page.getByRole('button', { name: /Stop/ })).toBeVisible();
});

test('Play-Along serializes Hear it and disables speaker output while grading', async ({ page }) => {
  await page.addInitScript(() => {
    const state = {
      oscillators: [] as Array<{ stopCalls: number; disconnected: number }>,
      gains: [] as Array<{ cancelled: number; disconnected: number }>,
    };
    class FakeAudioContext {
      state: AudioContextState = 'running';
      currentTime = 0;
      destination = {};
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createOscillator() {
        const record = { stopCalls: 0, disconnected: 0 };
        state.oscillators.push(record);
        return {
          type: 'sine',
          frequency: { value: 0 },
          onended: null as (() => void) | null,
          connect() { return this; },
          disconnect: () => { record.disconnected += 1; },
          start: () => undefined,
          stop: () => { record.stopCalls += 1; },
        };
      }
      createGain() {
        const record = { cancelled: 0, disconnected: 0 };
        state.gains.push(record);
        return {
          gain: {
            value: 0.22,
            cancelScheduledValues: () => { record.cancelled += 1; },
            setValueAtTime: () => undefined,
            exponentialRampToValueAtTime: () => undefined,
          },
          connect() { return this; },
          disconnect: () => { record.disconnected += 1; },
        };
      }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: () => new Promise(() => undefined) },
    });
    (window as unknown as { __referenceToneTest: unknown }).__referenceToneTest = state;
  });

  await page.goto('/practice/play-along');
  const hear = page.getByRole('button', { name: 'Hear it', exact: true }).first();
  await hear.click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __referenceToneTest: { oscillators: unknown[] } }).__referenceToneTest.oscillators.length)).toBe(8);
  const stopReference = page.getByRole('button', { name: 'Stop', exact: true });
  await expect(stopReference).toBeEnabled();
  await expect(stopReference).toHaveAttribute('aria-pressed', 'true');

  await stopReference.click();
  await expect(hear).toBeEnabled();
  await expect(hear).toHaveAttribute('aria-pressed', 'false');
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __referenceToneTest: { oscillators: Array<{ stopCalls: number }>; gains: Array<{ cancelled: number }> } }
  ).__referenceToneTest.oscillators.every((oscillator) => oscillator.stopCalls >= 2)
    && (window as unknown as { __referenceToneTest: { gains: Array<{ cancelled: number }> } }).__referenceToneTest.gains.every((gain) => gain.cancelled >= 1))).toBe(true);

  await hear.click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __referenceToneTest: { oscillators: unknown[] } }).__referenceToneTest.oscillators.length)).toBe(16);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Hear it', exact: true })).toBeDisabled();
  await expect.poll(() => page.evaluate(() => (
    window as unknown as { __referenceToneTest: { oscillators: Array<{ stopCalls: number }> } }
  ).__referenceToneTest.oscillators.every((oscillator) => oscillator.stopCalls >= 2))).toBe(true);
});

test('an ended audio track from a minimal MediaStream fixture returns the tuner to microphone recovery', async ({ page }) => {
  await page.addInitScript(() => {
    const state: { requests: number; ended?: () => void; stops: number } = { requests: 0, stops: 0 };
    class FakeAudioContext {
      state: AudioContextState = 'running';
      sampleRate = 48_000;
      destination = {};
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createMediaStreamSource() { return { connect: () => undefined, disconnect: () => undefined }; }
      createScriptProcessor() { return { connect: () => undefined, disconnect: () => undefined, onaudioprocess: null }; }
      createGain() { return { gain: { value: 1 }, connect: () => undefined, disconnect: () => undefined }; }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: async () => {
          state.requests += 1;
          const track: { kind: 'audio'; readyState: 'live'; onended?: () => void; stop: () => void } = {
            kind: 'audio',
            readyState: 'live',
            stop: () => { state.stops += 1; },
          };
          state.ended = () => track.onended?.();
          // Deliberately omit getAudioTracks: this matches simple test and
          // embedded-browser MediaStream fixtures that only implement getTracks.
          return { getTracks: () => [track] };
        },
      },
    });
    (window as unknown as { __trackEndedTest: unknown }).__trackEndedTest = state;
  });

  await page.goto('/practice');
  await expect.poll(() => page.evaluate(() => (window as unknown as { __trackEndedTest: { requests: number } }).__trackEndedTest.requests)).toBe(1);
  await page.evaluate(() => (window as unknown as { __trackEndedTest: { ended?: () => void } }).__trackEndedTest.ended?.());
  await expect(page.getByRole('button', { name: 'Turn on microphone' })).toBeVisible();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __trackEndedTest: { stops: number } }).__trackEndedTest.stops)).toBe(1);
});

test('the real pitch Worker accepts a transferred PCM frame and returns its matching result', async ({ page }) => {
  await page.goto('/practice');
  const frame = await page.evaluate(async () => {
    const module = await import('/src/workers/pitchDetection.worker.ts?worker');
    const worker = new module.default();
    const pcm = new Float32Array(4096);
    for (let index = 0; index < pcm.length; index += 1) {
      pcm[index] = 0.5 * Math.sin((2 * Math.PI * 440 * index) / 48_000);
    }
    return await new Promise<{ timestampMs: number; valid: boolean; frequencyHz: number | null; concertNote: string | null; writtenNote: string | null; cents: number | null }>((resolve, reject) => {
      const timeout = window.setTimeout(() => reject(new Error('pitch Worker did not respond')), 5_000);
      worker.onmessage = (event: MessageEvent<{ timestampMs: number; frame: { is_valid_for_recording: boolean; frequency_hz: number | null; concert_note_name: string | null; concert_octave: number | null; written_note_name: string | null; written_octave: number | null; cents_deviation: number | null } }>) => {
        window.clearTimeout(timeout);
        worker.terminate();
        const result = event.data.frame;
        resolve({
          timestampMs: event.data.timestampMs,
          valid: result.is_valid_for_recording,
          frequencyHz: result.frequency_hz,
          concertNote: `${result.concert_note_name}${result.concert_octave}`,
          writtenNote: `${result.written_note_name}${result.written_octave}`,
          cents: result.cents_deviation,
        });
      };
      worker.postMessage({ type: 'detect', pcm: pcm.buffer, sampleRate: 48_000, instrumentId: 'trumpet', referencePitch: 440, timestampMs: 42 }, [pcm.buffer]);
    });
  });
  expect(frame.timestampMs).toBe(42);
  expect(frame.valid).toBe(true);
  expect(frame.frequencyHz).toBeCloseTo(440, 0);
  expect(frame.concertNote).toBe('A4');
  expect(frame.writtenNote).toBe('B4');
  expect(frame.cents).toBeCloseTo(0, 0);
});

test('a silent runtime Worker falls back after its bounded backlog watchdog', async ({ page }) => {
  await page.addInitScript(() => {
    const state: { processor?: (event: { inputBuffer: { getChannelData: () => Float32Array } }) => void; workerPosts: number; workerTerminates: number } = {
      workerPosts: 0,
      workerTerminates: 0,
    };
    class SilentWorker {
      onmessage: ((event: MessageEvent) => void) | null = null;
      onerror: (() => void) | null = null;
      postMessage() { state.workerPosts += 1; }
      terminate() { state.workerTerminates += 1; }
    }
    class FakeAudioContext {
      state: AudioContextState = 'running';
      sampleRate = 48_000;
      destination = {};
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createMediaStreamSource() { return { connect: () => undefined, disconnect: () => undefined }; }
      createScriptProcessor() {
        const processor = { connect: () => undefined, disconnect: () => undefined, onaudioprocess: null as typeof state.processor };
        Object.defineProperty(processor, 'onaudioprocess', {
          get: () => state.processor,
          set: (value) => { state.processor = value; },
        });
        return processor;
      }
      createGain() { return { gain: { value: 1 }, connect: () => undefined, disconnect: () => undefined }; }
    }
    Object.defineProperty(window, 'Worker', { configurable: true, value: SilentWorker });
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: { getUserMedia: async () => ({ getTracks: () => [{ kind: 'audio', readyState: 'live', stop() {} }] }) },
    });
    (window as unknown as { __workerWatchdogTest: unknown }).__workerWatchdogTest = state;
  });

  await page.goto('/practice');
  await page.getByRole('button', { name: 'Turn on microphone' }).click();
  await expect.poll(() => page.evaluate(() => Boolean((window as unknown as { __workerWatchdogTest: { processor?: unknown } }).__workerWatchdogTest.processor))).toBe(true);
  await page.evaluate(() => {
    const state = (window as unknown as { __workerWatchdogTest: { processor?: (event: { inputBuffer: { getChannelData: () => Float32Array } }) => void } }).__workerWatchdogTest;
    const event = { inputBuffer: { getChannelData: () => new Float32Array(4096) } };
    state.processor?.(event);
    state.processor?.(event);
    state.processor?.(event);
  });
  await expect.poll(() => page.evaluate(() => (window as unknown as { __workerWatchdogTest: { workerPosts: number } }).__workerWatchdogTest.workerPosts)).toBe(3);
  await page.waitForTimeout(1_550);
  await page.evaluate(() => {
    const state = (window as unknown as { __workerWatchdogTest: { processor?: (event: { inputBuffer: { getChannelData: () => Float32Array } }) => void } }).__workerWatchdogTest;
    state.processor?.({ inputBuffer: { getChannelData: () => new Float32Array(4096) } });
  });
  await expect.poll(() => page.evaluate(() => (window as unknown as { __workerWatchdogTest: { workerTerminates: number } }).__workerWatchdogTest.workerTerminates)).toBe(1);
});

test('Stop cancels scheduled count-in clicks and unmount closes the metronome context', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { closeCalls: 0, oscillators: [] as Array<{ stops: number[] }> };
    class FakeAudioContext {
      state: AudioContextState = 'running';
      currentTime = 0;
      destination = {};
      resume() { this.state = 'running'; return Promise.resolve(); }
      close() { state.closeCalls += 1; this.state = 'closed'; return Promise.resolve(); }
      createOscillator() {
        const record = { stops: [] as number[] };
        state.oscillators.push(record);
        return {
          type: 'sine',
          frequency: { setValueAtTime: () => undefined },
          connect() { return this; },
          disconnect: () => undefined,
          start: () => undefined,
          stop: (time: number) => { record.stops.push(time); },
          onended: null,
        };
      }
      createGain() {
        return {
          gain: {
            setValueAtTime: () => undefined,
            exponentialRampToValueAtTime: () => undefined,
          },
          connect() { return this; },
          disconnect: () => undefined,
        };
      }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    (window as unknown as { __metronomeTest: unknown }).__metronomeTest = state;
  });

  await page.goto('/metronome');
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeTest: { oscillators: unknown[] } }).__metronomeTest.oscillators.length)).toBe(4);
  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeTest: { oscillators: Array<{ stops: number[] }> } }).__metronomeTest.oscillators.every((item) => item.stops.length >= 2))).toBe(true);

  await page.evaluate(() => {
    window.history.pushState({}, '', '/settings');
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page).toHaveURL(/\/settings$/);
  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeTest: { closeCalls: number } }).__metronomeTest.closeCalls)).toBe(1);
});

test('Metronome serializes rapid Start activation while AudioContext resume is pending', async ({ page }) => {
  await page.addInitScript(() => {
    let finishResume: (() => void) | undefined;
    const resumePending = new Promise<void>((resolve) => { finishResume = resolve; });
    const state = { contexts: 0, resumeCalls: 0, oscillators: 0 };
    class FakeAudioContext {
      state: AudioContextState = 'suspended';
      currentTime = 0;
      destination = {};
      constructor() { state.contexts += 1; }
      async resume() {
        state.resumeCalls += 1;
        await resumePending;
        this.state = 'running';
      }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createOscillator() {
        state.oscillators += 1;
        return {
          type: 'sine',
          frequency: { setValueAtTime: () => undefined },
          connect() { return this; },
          disconnect: () => undefined,
          start: () => undefined,
          stop: () => undefined,
          onended: null,
        };
      }
      createGain() {
        return {
          gain: {
            setValueAtTime: () => undefined,
            exponentialRampToValueAtTime: () => undefined,
          },
          connect() { return this; },
          disconnect: () => undefined,
        };
      }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    (window as unknown as { __metronomeStartTest: unknown }).__metronomeStartTest = {
      state,
      finishResume: () => finishResume?.(),
    };
  });

  await page.goto('/metronome');
  const start = page.getByRole('button', { name: 'Start', exact: true });
  await start.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });

  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeStartTest: { state: { contexts: number } } }).__metronomeStartTest.state.contexts)).toBe(1);
  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeStartTest: { state: { resumeCalls: number } } }).__metronomeStartTest.state.resumeCalls)).toBe(1);
  await page.evaluate(() => (window as unknown as { __metronomeStartTest: { finishResume: () => void } }).__metronomeStartTest.finishResume());

  await expect(page.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __metronomeStartTest: { state: { oscillators: number } } }).__metronomeStartTest.state.oscillators)).toBe(4);
});

test('sheet delete confirmation traps focus, closes on Escape, and restores focus', async ({ page }) => {
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
  await page.goto('/practice/score');
  await page.locator('input[type="file"][aria-label="Choose Files"]').setInputFiles({ name: 'focus-test.png', mimeType: 'image/png', buffer: png });
  await expect(page.getByRole('img', { name: /Sheet music.*focus-test\.jpg/i })).toBeVisible();
  const moreOptions = page.getByRole('button', { name: 'More options' });
  await moreOptions.click();
  await page.getByRole('menuitem', { name: /Delete this page/i }).click();

  const dialog = page.getByRole('dialog', { name: 'Remove this page?' });
  await expect(dialog).toBeVisible();
  const cancel = dialog.getByRole('button', { name: 'Cancel' });
  const remove = dialog.getByRole('button', { name: 'Remove', exact: true });
  await expect(cancel).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(remove).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toHaveCount(0);
  await expect(moreOptions).toBeFocused();
});
