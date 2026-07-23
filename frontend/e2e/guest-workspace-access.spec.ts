import { readFile } from 'node:fs/promises';
import { expect, test, type Page, type Route } from 'playwright/test';

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
  audio_duration_seconds: 5,
  audio_size_bytes: 44,
  audio_uploaded_at: '2026-07-22T18:00:05.000Z',
  guest_audio_data_url: 'data:audio/wav;base64,UklGRg==',
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
    localStorage.setItem('brasstune.guestAccess', 'true');
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
  await expect(page.locator('audio[src^="data:audio/wav"]')).toBeVisible();

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
  await expect(signIn).toHaveAttribute('href', '/?next=%2Fpractice%2Fplay-along%3Fexercise%3Dcmaj');

  await page.goto('/auth/sign-in?next=%2Fpractice%2Fplay-along%3Fexercise%3Dcmaj');
  const guestEscape = page.getByRole('link', { name: 'Keep practicing as a guest' });
  await expect(guestEscape).toHaveAttribute('href', '/practice/play-along?exercise=cmaj');
  await guestEscape.click();
  await expect(page).toHaveURL(/\/practice\/play-along\?exercise=cmaj$/);
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.guestAccess'))).toBe('true');
});

test('auth guest escape rejects an external next target in the browser', async ({ page }) => {
  await seedGuestWorkspace(page);
  await installSignedOutFixture(page);

  await page.goto('/auth/sign-in?next=https%3A%2F%2Fevil.example%2Fsteal');
  const guestEscape = page.getByRole('link', { name: 'Keep practicing as a guest' });
  await expect(guestEscape).toHaveAttribute('href', '/home');
  await guestEscape.click();
  await expect(page).toHaveURL(/\/practice$/);
});
