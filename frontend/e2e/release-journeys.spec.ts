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
    ['/ensemble', /Ensemble access/i],
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

test('guest ensemble route does not expose director report controls', async ({ page }) => {
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: /ensemble access/i })).toBeVisible();
  await expect(page.getByText(/membership required/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Director briefing|Print report|Roster admin|Section trends|Top problem notes/i);
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
  await expect(stopButton).toBeVisible({ timeout: 30_000 });
  await expect.poll(async () => page.locator('.note-history .history-row').count(), { timeout: 15_000 }).toBeGreaterThan(0);
  await expect.poll(async () => page.getByRole('timer').textContent(), { timeout: 10_000 }).toMatch(/0:0[2-9]/);
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
  await expect.poll(() => page.evaluate(() => {
    const sessions = JSON.parse(localStorage.getItem('brasstune.guestSessions.v1') ?? '[]');
    return sessions[0]?.note_stats?.length ?? 0;
  })).toBeGreaterThan(0);
  await expect(page.locator('body')).not.toContainText(/Authentication required/i);
  await page.evaluate(() => {
    window.history.pushState({}, '', '/practice');
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByText(/Import recording/i)).toBeVisible();
  await expect(page.getByText(/Choose audio or video file/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Camera|phone camera picker|Record or choose a camera video/i);

  await page.evaluate(() => {
    window.history.pushState({}, '', '/analytics');
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page).toHaveURL(/\/analytics$/);
  await expect(page.getByText(/Using guest sessions saved in this browser/i)).toBeVisible();
  await expect(page.locator('.status-badge').filter({ hasText: /measured notes/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Analytics are available after sign-in/i);

  await page.evaluate(() => {
    window.history.pushState({}, '', '/coach');
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page).toHaveURL(/\/coach$/);
  await expect(page.getByText(/Guest intonation plan/i)).toBeVisible();
  await expect(page.getByText(/Using guest sessions saved in this browser/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Coach recommendations are available after sign-in/i);

  await page.evaluate(() => {
    window.history.pushState({}, '', '/progress');
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
  await expect(page).toHaveURL(/\/progress$/);
  await expect(page.getByText(/Guest browser data/i)).toBeVisible();
  await expect(page.getByText(/Using guest sessions saved in this browser/i)).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Progress sync is available after sign-in/i);
});

test('tiny-phone practice controls stay clear of bottom navigation', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/practice');
  const recordButton = page.getByRole('button', { name: /start recording/i });
  const controls = page.locator('.tuner-surface .session-controls');
  const bottomNav = page.locator('.floating-tabbar');
  await expect(recordButton).toBeVisible();
  await expect(controls).toBeVisible();
  await expect(bottomNav).toBeVisible();
  const controlsBox = await controls.boundingBox();
  const navBox = await bottomNav.boundingBox();
  expect(controlsBox).not.toBeNull();
  expect(navBox).not.toBeNull();
  expect(controlsBox!.y + controlsBox!.height).toBeLessThanOrEqual(navBox!.y - 2);
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
    data: { username: 'jordan', instrument_id: 'trombone' },
  });
  expect([200, 409]).toContain(allowed.status());
});
