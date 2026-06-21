import { expect, test } from 'playwright/test';

const apiBaseURL = process.env.E2E_API_BASE_URL ?? 'http://127.0.0.1:8000';
const localAdminEnabled = process.env.E2E_START_LOCAL_SERVERS !== '0';

test.beforeEach(async ({ page, request }) => {
  if (localAdminEnabled) {
    await request.post(`${apiBaseURL}/api/admin/demo-data/repair`).catch(() => undefined);
  }
  await page.addInitScript(() => {
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .filter((key) => key !== 'brasstune.theme')
      .forEach((key) => localStorage.removeItem(key));
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.demoMode', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
});

test('critical routes render identifiable content', async ({ page }) => {
  const routes = [
    ['/', /Sign in or start a guest practice session/i],
    ['/home', /Today's intonation focus/i],
    ['/practice', /Live tuner cockpit/i],
    ['/metronome', /Metronome/i],
    ['/practice/score', /Score practice/i],
    ['/sessions', /Practice timeline/i],
    ['/analytics', /Analytics/i],
    ['/progress', /Progress/i],
    ['/coach', /Coach/i],
    ['/ensemble', /Director briefing/i],
    ['/settings', /Practice preferences/i],
    ['/settings/audio-lab', /Audio Calibration Lab|Calibration/i],
    ['/auth/sign-in', /Welcome back/i],
    ['/auth/sign-up', /Start tracking/i],
    ['/auth/reset-password', /Reset password/i],
    ['/privacy', /Privacy Policy/i],
    ['/terms', /Terms of Service/i],
    ['/support', /Support/i],
  ] as const;

  for (const [route, text] of routes) {
    await page.goto(route);
    await expect(page).toHaveURL(new RegExp(`${route === '/' ? '/?$' : route.replace('/', '\\/')}`));
    await expect(page.getByRole('main').getByText(text).first()).toBeVisible();
    await expect(page.locator('.content')).toBeVisible();
    await expect(page.locator('body')).not.toContainText(/Supabase env vars|FastAPI|Start the FastAPI server|Authentication required|Developer testing|MVP|seeded ensemble|phone camera picker/i);
  }
});

test('auth unavailable surfaces route testers into guest practice', async ({ page }) => {
  await page.goto('/auth/reset-password');
  await expect(page.getByText(/accounts are not enabled in this build yet/i)).toBeVisible();
  await expect(page.getByRole('link', { name: /continue as guest/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Supabase|VITE_SUPABASE|env vars/i);

  await page.goto('/auth/sign-in');
  await page.getByRole('link', { name: /continue as guest/i }).click();
  await expect(page).toHaveURL(/\/home$/);

  await page.goto('/auth/callback#error=access_denied&error_description=SUPABASE_SECRET_KEY%20missing');
  await expect(page.getByText(/accounts are not enabled in this build yet/i)).toBeVisible();
  await expect(page.getByRole('link', { name: /continue as guest/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/SUPABASE|SECRET_KEY|Supabase/i);
});

test('root gateway starts guest practice and persists theme selection', async ({ page }) => {
  await page.addInitScript(() => localStorage.removeItem('brasstune.guestAccess'));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /sign in or start a guest practice session/i })).toBeVisible();
  await page.getByLabel(/theme/i).selectOption('brass-day');
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe('brass-day');
  await page.reload();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.theme'))).toBe('brass-day');
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.theme)).toBe('brass-day');
  await page.getByRole('button', { name: /continue as guest/i }).click();
  await expect(page).toHaveURL(/\/home$/);
  await expect(page.getByText(/Today's intonation focus/i)).toBeVisible();
});

test('onboarding traps keyboard focus and closes with Escape', async ({ page }) => {
  await page.goto('/settings');
  await page.getByRole('button', { name: /reopen onboarding/i }).click();
  const dialog = page.getByRole('dialog', { name: /choose your brass voice/i });
  await expect(dialog).toBeVisible();
  await expect(page.getByRole('button', { name: /close onboarding/i })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
});

test('demo recording creates a reviewable session with playback surface', async ({ page }) => {
  await page.goto('/practice');
  const startButton = page.getByRole('button', { name: /start recording/i });
  await expect(startButton).toBeVisible();
  await expect(startButton).toBeEnabled();
  const backendSessionCalls: string[] = [];
  page.on('request', (request) => {
    const path = new URL(request.url()).pathname;
    if (request.method() === 'POST' && /\/api\/sessions\/.+(samples|stop|audio)|\/api\/sessions\/start$/.test(path)) {
      backendSessionCalls.push(`${request.method()} ${path}`);
    }
  });
  await startButton.click();
  const stopButton = page.getByRole('button', { name: /stop recording/i });
  await expect(stopButton).toBeVisible({ timeout: 15_000 });
  await expect.poll(async () => page.locator('.note-history .history-row').count(), { timeout: 15_000 }).toBeGreaterThan(0);
  await stopButton.click();
  const reviewLink = page.getByRole('link', { name: /review session/i });
  await expect(reviewLink).toBeVisible({ timeout: 20_000 });
  await expect(reviewLink).toHaveAttribute('href', /\/sessions\/-/);
  expect(backendSessionCalls).toEqual([]);
  await reviewLink.scrollIntoViewIfNeeded();
  const reviewHref = await reviewLink.getAttribute('href');
  expect(reviewHref).toMatch(/\/sessions\/-/);
  await reviewLink.click();
  await expect(page).toHaveURL(/\/sessions\/-/);
  await expect(page.getByRole('heading', { name: /Relisten/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Note performance/i })).toBeVisible();
  await expect(page.getByText(/guest session saved on this device/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Authentication required/i);
  await page.goto('/practice');
  await expect(page.getByText(/Import recording/i)).toBeVisible();
  await expect(page.getByText(/Choose audio or video file/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Camera|phone camera picker|Record or choose a camera video/i);
});

test('settings exposes export before account deletion and legal links', async ({ page }) => {
  await page.goto('/settings');
  await expect(page.getByRole('link', { name: /privacy/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /terms/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /support/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /export account data/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /delete account/i })).toBeDisabled();
  await expect(page.locator('body')).not.toContainText(/MVP|Developer testing|seeded ensemble|FastAPI|Supabase env vars/i);
});

test('server-side ensemble authorization rejects forbidden writes', async ({ request }) => {
  const denied = await request.post(`${apiBaseURL}/api/ensemble/groups/1/members/by-username`, {
    headers: { Authorization: 'Bearer dev-user-1' },
    data: { username: 'maya', instrument_id: 'horn' },
  });
  expect(denied.status()).toBe(403);

  const allowed = await request.post(`${apiBaseURL}/api/ensemble/groups/1/members/by-username`, {
    headers: { Authorization: 'Bearer dev-user-2' },
    data: { username: 'maya', instrument_id: 'horn' },
  });
  expect(allowed.status()).toBe(200);
});
