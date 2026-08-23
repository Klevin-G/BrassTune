import { readFile } from 'node:fs/promises';
import { expect, test, type Page, type Route } from 'playwright/test';

// 100 ms of unsigned 8-bit PCM silence at 8 kHz. Keep this a parseable WAV so
// the listen-back journey tests browser metadata readiness rather than a broken
// fixture masquerading as an audio failure.
const validGuestWavDataUrl = 'data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YSADAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA==';

const guestSession = {
  id: -101,
  user_id: 0,
  instrument_id: 'trombone',
  name: 'Private guest audio',
  started_at: '2026-07-22T18:00:00.000Z',
  ended_at: '2026-07-22T18:00:05.000Z',
  created_at: '2026-07-22T18:00:00.000Z',
  duration_seconds: 5,
  reference_pitch_hz: 440,
  notes_count: 1,
  average_signed_cents: 1,
  average_abs_cents: 1,
  in_tune_percentage: 100,
  audio_available: true,
  audio_mime_type: 'audio/wav',
  audio_duration_seconds: 0.1,
  audio_size_bytes: 844,
  audio_uploaded_at: '2026-07-22T18:00:05.000Z',
  guest_audio_data_url: validGuestWavDataUrl,
  guest_session: true,
  samples_count: 0,
  note_events: [],
  note_stats: [],
  heatmap: [],
  recommendations: [],
  frames: [],
};

const cloudSession = {
  id: 42,
  user_id: 99,
  instrument_id: 'trumpet',
  name: 'Account recording',
  started_at: '2026-07-22T19:00:00.000Z',
  ended_at: '2026-07-22T19:01:00.000Z',
  created_at: '2026-07-22T19:00:00.000Z',
  duration_seconds: 60,
  reference_pitch_hz: 440,
  notes_count: 8,
  average_signed_cents: 2,
  average_abs_cents: 3,
  in_tune_percentage: 88,
  audio_available: false,
};

function seedGuestWorkspace(page: Page) {
  return page.addInitScript((session) => {
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([session]));
    sessionStorage.setItem('brasstune.guestAccess', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.onboardingComplete', 'true');
  }, guestSession);
}

const signedInAuthModule = `
const session = { access_token: 'workspace-e2e-token', user: { id: 'workspace-user' } };
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    getSession: async () => ({ data: { session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({ error: null }),
    signInWithPassword: async () => ({ data: { session }, error: null }),
    signUp: async () => ({ data: { session }, error: null }),
  },
};
`;

const signedOutAuthModule = `
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    getSession: async () => ({ data: { session: null } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({ error: null }),
    signInWithPassword: async () => ({ data: { session: null }, error: null }),
    signUp: async () => ({ data: { session: null }, error: null }),
    resetPasswordForEmail: async () => ({ error: null }),
  },
};
`;

async function installSignedInFixture(page: Page) {
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: signedInAuthModule,
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
        id: 99,
        supabase_user_id: 'workspace-user',
        username: 'workspace-player',
        display_name: 'Workspace Player',
        email: 'workspace@example.test',
        role: 'student',
        primary_instrument_id: 'trumpet',
        onboarding_completed_at: '2026-07-22T19:00:00.000Z',
      });
    }
    if (path === '/api/sessions') return json([cloudSession]);
    if (path === '/api/users/me/export.zip') {
      return route.fulfill({ status: 200, contentType: 'application/zip', body: 'account-only-export' });
    }
    return json({ detail: 'Not found' }, 404);
  });
}

async function installSignedOutFixture(page: Page) {
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: signedOutAuthModule,
  }));
}

test('guest workspace can list, review, play, and export its local recording', async ({ page }) => {
  await seedGuestWorkspace(page);

  await page.goto('/sessions');
  const guestLink = page.locator('a[href="/sessions/-101"]');
  await expect(guestLink).toBeVisible();
  await expect(guestLink).toContainText('Saved on this device');
  await page.getByRole('button', { name: 'Listen back' }).click();
  const audio = page.locator('audio[src^="data:audio/wav"]');
  await expect(audio).toBeVisible();
  await expect.poll(() => audio.evaluate((element) => element.readyState >= HTMLMediaElement.HAVE_METADATA)).toBe(true);

  // The source is valid; simulate the browser's decode/playback event to keep
  // the retry affordance deterministic across Chromium audio backends.
  await audio.evaluate((element) => {
    const originalLoad = element.load.bind(element);
    (window as typeof window & { __brassTuneAudioReloads?: number }).__brassTuneAudioReloads = 0;
    element.load = () => {
      const instrumentedWindow = window as typeof window & { __brassTuneAudioReloads?: number };
      instrumentedWindow.__brassTuneAudioReloads = (instrumentedWindow.__brassTuneAudioReloads ?? 0) + 1;
      originalLoad();
    };
  });
  await audio.evaluate((element) => element.dispatchEvent(new Event('error')));
  await expect(page.getByRole('alert')).toHaveText('Your browser cannot play this audio.');
  await page.getByRole('button', { name: 'Load playback' }).click();
  await expect.poll(() => page.evaluate(
    () => (window as typeof window & { __brassTuneAudioReloads?: number }).__brassTuneAudioReloads ?? 0,
  )).toBe(1);
  await expect(page.getByRole('alert')).toHaveCount(0);

  await page.goto('/sessions/-101');
  await expect(page.getByRole('heading', { name: 'Private guest audio' })).toBeVisible();
  await expect(page.locator('audio[src^="data:audio/wav"]')).toBeVisible();

  await page.goto('/settings');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export guest practice' }).click();
  const download = await downloadPromise;
  const path = await download.path();
  expect(path).not.toBeNull();
  expect(await readFile(path!, 'utf8')).toContain('Private guest audio');
});

test('signed-in surfaces never expose retained guest recordings or guest audio', async ({ page }) => {
  await seedGuestWorkspace(page);
  await installSignedInFixture(page);

  await page.goto('/sessions');
  await expect(page.locator('a[href="/sessions/42"]')).toBeVisible();
  await expect(page.locator('a[href="/sessions/-101"]')).toHaveCount(0);
  await expect(page.getByText('Saved on this device')).toHaveCount(0);
  await expect(page.locator('audio[src^="data:audio"]')).toHaveCount(0);

  await page.goto('/sessions/-101');
  await expect(page.getByRole('heading', { name: 'Recording not found' })).toBeVisible();
  await expect(page.getByText('Private guest audio')).toHaveCount(0);
  await expect(page.locator('audio[src^="data:audio"]')).toHaveCount(0);

  await page.goto('/settings');
  const exportRequest = page.waitForRequest((request) => new URL(request.url()).pathname === '/api/users/me/export.zip');
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export my data' }).click();
  await exportRequest;
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe('brasstune-account-export.zip');
});

test('configured auth preserves the current route and always offers a guest escape', async ({ page }) => {
  await seedGuestWorkspace(page);
  await installSignedOutFixture(page);

  await page.goto('/practice/play-along?exercise=cmaj');
  const signIn = page.getByRole('link', { name: 'Sign in' }).first();
  await expect(signIn).toHaveAttribute('href', '/?next=%2Fpractice%2Fscorer%3Fexercise%3Dcmaj');

  await page.goto('/auth/sign-in?next=%2Fpractice%2Fscorer%3Fexercise%3Dcmaj');
  const guestEscape = page.getByRole('button', { name: 'Keep practicing as a guest' });
  await expect(guestEscape).toBeEnabled();
  await guestEscape.click();
  await expect(page).toHaveURL(/\/practice\/scorer\?exercise=cmaj$/);
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.guestAccess'))).toBe('true');
});

test('retained guest practice does not restore guest access after a cold browser reopen', async ({ page }) => {
  // Do not use addInitScript here: it runs again on every navigation and would
  // incorrectly restore the tab-scoped access marker that this test is meant
  // to prove disappears when the browser closes.
  await page.goto('/');
  await page.evaluate((session) => {
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([session]));
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    sessionStorage.setItem('brasstune.guestAccess', 'true');
  }, guestSession);
  await page.goto('/sessions');
  await expect(page.locator('a[href="/sessions/-101"]')).toBeVisible();

  // Closing a browser tab discards sessionStorage but leaves guest practice
  // data in localStorage. Use a genuinely new page so React cannot retain an
  // in-memory guestMode value from the original page.
  await page.evaluate(() => {
    // A prior release persisted this value. It must not grant access after the
    // migration, even while the guest recording itself remains retained.
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
  const context = page.context();
  await page.close();
  const reopened = await context.newPage();
  await reopened.goto('/sessions');

  await expect(reopened).toHaveURL(/\/?\?next=%2Fsessions$/);
  await expect.poll(() => reopened.evaluate(() => localStorage.getItem('brasstune.guestSessions.v1'))).toContain('Private guest audio');
  await expect.poll(() => reopened.evaluate(() => sessionStorage.getItem('brasstune.guestAccess'))).toBeNull();
  await expect.poll(() => reopened.evaluate(() => localStorage.getItem('brasstune.guestAccess'))).toBeNull();

  // Data stays durable, but becomes reachable only after a fresh, explicit
  // guest entry in the reopened browser page.
  await reopened.getByRole('button', { name: 'Start practicing' }).click();
  await expect.poll(() => reopened.evaluate(() => sessionStorage.getItem('brasstune.guestAccess'))).toBe('true');
  await reopened.goto('/sessions');
  await expect(reopened.locator('a[href="/sessions/-101"]')).toBeVisible();
});

test('configured gateway makes account creation primary while guest practice stays secondary', async ({ page }) => {
  await installSignedOutFixture(page);
  await page.goto('/');

  const createAccount = page.getByRole('link', { name: 'Create free account' });
  const guest = page.getByRole('button', { name: 'Continue as guest' });
  await expect(createAccount).toBeVisible();
  await expect(guest).toBeVisible();
  await expect(createAccount).toHaveClass(/primary-button/);
  await expect(guest).toHaveClass(/ghost-button/);
  const [createBox, guestBox] = await Promise.all([createAccount.boundingBox(), guest.boundingBox()]);
  expect(createBox?.y).toBeLessThan(guestBox?.y ?? Number.POSITIVE_INFINITY);
  await expect(page.getByText(/jump right in|no account needed/i)).toHaveCount(0);
});

test('auth guest escape rejects a normalized protocol-relative next target in the browser', async ({ page }) => {
  await seedGuestWorkspace(page);
  await installSignedOutFixture(page);

  await page.goto('/auth/sign-in?next=%2F..%2F%2Fevil.example%2Fsteal');
  const guestEscape = page.getByRole('button', { name: 'Keep practicing as a guest' });
  await expect(guestEscape).toBeEnabled();
  await guestEscape.click();
  await expect(page).toHaveURL(/\/practice$/);
});
