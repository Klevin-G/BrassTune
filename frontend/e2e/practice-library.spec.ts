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
  await expect(page.locator('.floating-tabbar')).toHaveCount(0);
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

test('named metronome presets persist and the production service worker entry is available', async ({ page, request }) => {
  await page.goto('/metronome');
  await page.getByLabel('Preset name').fill('Audition tempo');
  await page.getByRole('button', { name: 'Save current setup' }).click();
  await expect(page.getByText('Saved “Audition tempo”.')).toBeVisible();
  await page.reload();
  await expect(page.getByRole('button', { name: /Audition tempo.*96 BPM/ })).toBeVisible();

  const serviceWorker = await request.get('/sw.js');
  expect(serviceWorker.ok()).toBeTruthy();
  expect((await serviceWorker.text()).length).toBeGreaterThan(100);
});

test('locale selection updates language, direction, manifest, Intl output, and preserves musical user text', async ({ page }) => {
  await page.goto('/settings');
  const locale = page.getByLabel('App language');
  await locale.selectOption('ar');
  await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/manifests/ar.webmanifest');
  await expect(page.getByRole('link', { name: 'الموالف' }).first()).toBeVisible();
  await page.goto('/practice');
  await expect(page.locator('.tuning-meter-track')).toHaveCSS('direction', 'ltr');

  await page.goto('/settings');
  await page.locator('.locale-selector select').selectOption('en-XA');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en-XA');
  await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', '/manifests/en-XA.webmanifest');
  await page.goto('/practice/play-along');
  await page.locator('.practice-builder summary').click();
  await page.locator('.practice-builder input').fill('A-G Warmup');
  await page.locator('.practice-builder textarea').fill('A B C D E F G');
  await page.locator('.practice-builder button').filter({ has: page.locator('svg') }).first().click();
  await expect(page.getByText(/A-G Warmup/).first()).toBeVisible();
  expect(await page.getByText(/A-G Warmup/).first().textContent()).toContain('A-G Warmup');
});

test('saved reflections are fully listed, editable, deletable, and persist user text verbatim', async ({ page }) => {
  await page.goto('/settings');
  await page.evaluate(() => {
    localStorage.setItem('brasstune.practiceLibrary.v1.guest', JSON.stringify({
      version: 1,
      customExercises: [],
      metronomePresets: [],
      favorites: [],
      recents: [],
      reflections: [
        { id: 'reflection-1', text: 'Keep A-G smooth.', createdAt: '2026-07-22T12:00:00.000Z' },
        { id: 'reflection-2', text: 'Breathe before Bb.', createdAt: '2026-07-21T12:00:00.000Z' },
      ],
      warmup: { elapsedSeconds: 0, stepIndex: 0, updatedAt: '2026-07-22T12:00:00.000Z' },
      weeklyGoal: { week: '2026-07-20', targetMinutes: 60, completedMinutes: 0, targetSessions: 3, completedSessions: 0 },
    }));
  });
  await page.reload();
  await expect(page.getByText('Keep A-G smooth.')).toBeVisible();
  await expect(page.getByText('Breathe before Bb.')).toBeVisible();
  await page.getByRole('button', { name: 'Edit reflection' }).first().click();
  await page.getByRole('textbox', { name: 'Edit reflection' }).fill('Keep A-G smooth — softer next time.');
  await page.getByRole('button', { name: 'Save reflection changes' }).click();
  await expect(page.getByText('Keep A-G smooth — softer next time.')).toBeVisible();
  await page.getByRole('button', { name: 'Delete reflection' }).last().click();
  await expect(page.getByText('Breathe before Bb.')).toHaveCount(0);
  await page.reload();
  await expect(page.getByText('Keep A-G smooth — softer next time.')).toBeVisible();
  await expect(page.getByText('Breathe before Bb.')).toHaveCount(0);
});
