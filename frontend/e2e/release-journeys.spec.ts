import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page, request }) => {
  await request.post('http://127.0.0.1:8000/api/admin/demo-data/repair').catch(() => undefined);
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
  });
});

test('critical routes render identifiable content', async ({ page }) => {
  const routes = [
    ['/', /Today's intonation focus/i],
    ['/practice', /Live tuner cockpit/i],
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
  }
});

test('auth reset and Apple surfaces are wired', async ({ page }) => {
  await page.goto('/auth/reset-password');
  await expect(page.getByRole('button', { name: /send reset link/i })).toBeDisabled();
  await expect(page.getByLabel(/email/i)).toBeVisible();

  await page.goto('/auth/sign-in');
  await expect(page.getByRole('button', { name: /continue with apple/i })).toBeDisabled();
  await page.goto('/auth/callback#error=access_denied&error_description=The%20user%20cancelled');
  await expect(page.getByText(/not completed/i)).toBeVisible();
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
  await page.getByRole('button', { name: /start recording/i }).click();
  await expect(page.getByRole('button', { name: /stop recording/i })).toBeVisible();
  await page.waitForTimeout(2200);
  await page.getByRole('button', { name: /stop recording/i }).click();
  await expect(page.getByRole('link', { name: /review session/i })).toBeVisible();
  await page.getByRole('link', { name: /review session/i }).click();
  await expect(page).toHaveURL(/\/sessions\/\d+/);
  await expect(page.getByRole('heading', { name: /Relisten/i })).toBeVisible();
  await expect(page.getByRole('heading', { name: /Note performance/i })).toBeVisible();
});

test('settings exposes export before account deletion and legal links', async ({ page }) => {
  await page.goto('/settings');
  await expect(page.getByRole('link', { name: /privacy/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /terms/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /export account data/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /delete account/i })).toBeDisabled();
});

test('server-side ensemble authorization rejects forbidden writes', async ({ request }) => {
  const denied = await request.post('http://127.0.0.1:8000/api/ensemble/groups/1/members/by-username', {
    headers: { Authorization: 'Bearer dev-user-1' },
    data: { username: 'maya', instrument_id: 'horn' },
  });
  expect(denied.status()).toBe(403);

  const allowed = await request.post('http://127.0.0.1:8000/api/ensemble/groups/1/members/by-username', {
    headers: { Authorization: 'Bearer dev-user-2' },
    data: { username: 'maya', instrument_id: 'horn' },
  });
  expect(allowed.status()).toBe(200);
});
