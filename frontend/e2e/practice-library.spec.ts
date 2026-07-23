import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (sessionStorage.getItem('e2e.practiceLibrary.initialized') !== 'true') {
      Object.keys(localStorage).filter((key) => key.startsWith('brasstune.')).forEach((key) => localStorage.removeItem(key));
      localStorage.setItem('brasstune.onboardingComplete', 'true');
      localStorage.setItem('brasstune.guestAccess', 'true');
      localStorage.setItem('brasstune.demoMode', 'true');
      sessionStorage.setItem('e2e.practiceLibrary.initialized', 'true');
    }
  });
});

test('mobile practice home exposes resumable warm-up, drone, goals, packs, and visible focus exit', async ({ page }, testInfo) => {
  const consoleErrors: string[] = [];
  page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto('/practice');
  await expect(page.getByRole('heading', { name: 'Guided 5-minute warm-up' })).toBeVisible();
  await page.getByRole('button', { name: 'Start warm-up' }).click();
  await expect(page.getByRole('button', { name: 'Pause' })).toBeVisible();
  await page.getByRole('button', { name: 'Pause' }).click();

  await page.getByLabel('Practice tool').getByText('Drone / intervals').click();
  await expect(page.getByRole('heading', { name: 'Drone and interval tone' })).toBeVisible();
  await expect(page.getByText(/headphones/i)).toBeVisible();

  await page.getByLabel('Goal in minutes').fill('90');
  await page.getByRole('button', { name: 'Save goal' }).click();
  await expect(page.getByText('0 of 90 minutes')).toBeVisible();

  await page.getByRole('button', { name: 'Start pack' }).first().click();
  await expect(page.getByRole('button', { name: 'Exit focus' })).toBeVisible();
  await expect(page.locator('.floating-tab-bar')).toHaveCount(0);
  await page.getByRole('button', { name: 'Exit focus' }).click();

  await page.screenshot({ path: testInfo.outputPath('mobile-practice.png') });
  await expect(page.locator('.vite-error-overlay')).toHaveCount(0);
  const dimensions = await page.evaluate(() => ({ clientWidth: document.documentElement.clientWidth, scrollWidth: document.documentElement.scrollWidth }));
  expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth);
  expect(consoleErrors).toEqual([]);
});

test('custom play-along exercises validate, persist, and can be favorited', async ({ page }) => {
  await page.goto('/practice/play-along');
  await page.getByText('Build a custom exercise').click();
  await page.getByLabel('Exercise name').fill('Lip slur check');
  await page.getByLabel('Notes').fill('C nope');
  await page.getByRole('button', { name: 'Save and select' }).click();
  await expect(page.getByRole('alert')).toContainText('not a note');

  await page.getByLabel('Notes').fill('C E G Bb');
  await page.getByRole('button', { name: 'Save and select' }).click();
  await expect(page.getByText('Your custom exercise · 4 notes')).toBeVisible();
  await page.getByRole('button', { name: 'Favorite', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Favorited', exact: true })).toHaveAttribute('aria-pressed', 'true');

  await page.reload();
  await expect(page.getByText('Your custom exercise · 4 notes')).toBeVisible();
});

test('named metronome presets persist and offline shell never owns API or audio requests', async ({ page, request }) => {
  await page.goto('/metronome');
  await page.getByLabel('Preset name').fill('Audition tempo');
  await page.getByRole('button', { name: 'Save current setup' }).click();
  await expect(page.getByText('Saved “Audition tempo”.')).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button', { name: /Audition tempo.*96 BPM/ })).toBeVisible();

  const serviceWorker = await request.get('/sw.js');
  expect(serviceWorker.ok()).toBeTruthy();
  const source = await serviceWorker.text();
  expect(source).toContain("url.pathname.startsWith('/api')");
  expect(source).toContain("['audio', 'video']");
});
