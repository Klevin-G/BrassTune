import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
    localStorage.setItem('brasstune.demoMode', 'true');
  });
});

async function waitForInstalledShell(page: import('playwright/test').Page) {
  await page.goto('/practice');
  await page.evaluate(async () => {
    const registration = await navigator.serviceWorker.ready;
    await registration.update();
    if (!navigator.serviceWorker.controller) {
      await new Promise<void>((resolve) => navigator.serviceWorker.addEventListener('controllerchange', () => resolve(), { once: true }));
    }
  });
  await expect.poll(() => page.evaluate(async () => (await caches.keys()).some((key) => key.includes('workbox-precache')))).toBe(true);
}

test('production service worker installs and opens a lazy deep link offline', async ({ page, context, request }) => {
  const manifest = await request.get('/manifest.webmanifest');
  expect(manifest.ok()).toBeTruthy();
  expect(await manifest.json()).toMatchObject({ id: '/practice', start_url: '/practice', display: 'standalone', lang: 'en' });
  const worker = await request.get('/sw.js');
  expect(worker.ok()).toBeTruthy();

  await waitForInstalledShell(page);
  await context.setOffline(true);
  try {
    expect(await page.evaluate(() => fetch('/api/health').then(() => true).catch(() => false))).toBe(false);
    expect(await page.evaluate(() => fetch('/recording.webm').then(() => true).catch(() => false))).toBe(false);
    await page.goto('/practice/play-along?exercise=cmaj', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Play-Along' })).toBeVisible();
    await expect(page.getByRole('button', { name: /^C major Start here$/i })).toHaveAttribute('aria-pressed', 'true');
  } finally {
    await context.setOffline(false);
  }
});

test('an installed practice pack can cross a lazy route boundary offline', async ({ page, context }) => {
  await waitForInstalledShell(page);
  await page.getByRole('button', { name: 'Start pack' }).first().click();
  await expect(page.getByRole('button', { name: 'Exit focus' })).toBeVisible();

  await context.setOffline(true);
  try {
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page).toHaveURL(/tool=drone/);
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page).toHaveURL(/practice\/play-along\?exercise=cmaj/);
    await expect(page.getByRole('heading', { name: 'Play-Along' })).toBeVisible();
  } finally {
    await context.setOffline(false);
  }
});
