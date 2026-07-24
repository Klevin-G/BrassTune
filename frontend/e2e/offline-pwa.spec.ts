import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
    localStorage.setItem('brasstune.demoMode', 'true');
    let pageHidden = false;
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      get: () => pageHidden,
    });
    (window as typeof window & { __setPracticeHidden?: (hidden: boolean) => void }).__setPracticeHidden = (hidden) => {
      pageHidden = hidden;
      document.dispatchEvent(new Event('visibilitychange'));
    };
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

async function workspaceSnapshot(page: import('playwright/test').Page) {
  return page.evaluate(() => {
    const raw = sessionStorage.getItem('brasstune.practiceWorkspace.v1.guest');
    return raw ? JSON.parse(raw) : null;
  });
}

test('production service worker executes and reloads a lazy scorer deep link offline', async ({ page, context, request }) => {
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
    await page.goto('/practice/scorer?exercise=cmaj', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Practice Scorer' })).toBeVisible();
    await expect(page.getByRole('button', { name: /^C major Start here$/i })).toHaveAttribute('aria-pressed', 'true');
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(page).toHaveURL(/practice\/scorer\?exercise=cmaj/);
    await expect(page.getByRole('heading', { name: 'Practice Scorer' })).toBeVisible();
  } finally {
    await context.setOffline(false);
  }
});

test('an installed pack executes offline, persists bounded progress, pauses on background, and completes after reload', async ({ page, context }) => {
  await waitForInstalledShell(page);
  await page.getByRole('button', { name: 'Start pack' }).first().click();
  await expect(page.getByRole('button', { name: 'Exit focus' })).toBeVisible();
  await page.getByRole('button', { name: 'Start warm-up' }).click();
  await expect.poll(async () => (await workspaceSnapshot(page))?.elapsedSecondsByStep?.['guided-5'] ?? 0).toBeGreaterThan(0);

  await context.setOffline(true);
  try {
    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('button', { name: 'Exit focus' })).toBeVisible();
    const restored = await workspaceSnapshot(page);
    expect(restored).toMatchObject({
      version: 1,
      packId: 'daily-foundations',
      packVersion: 1,
      stepIndex: 0,
      completedStepIds: [],
    });
    expect(restored).not.toHaveProperty('pack');

    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page).toHaveURL(/tool=drone/);
    await expect(page.getByLabel('Written note')).toHaveValue('70');
    await page.getByLabel('Interval').selectOption('2');
    await page.getByRole('button', { name: 'Start tone' }).click();
    await expect(page.getByRole('button', { name: 'Stop tone' })).toBeVisible();

    await page.evaluate(() => {
      (window as typeof window & { __setPracticeHidden: (hidden: boolean) => void }).__setPracticeHidden(true);
    });
    await expect(page.getByRole('button', { name: 'Start tone' })).toBeVisible();
    const pausedAt = (await workspaceSnapshot(page)).elapsedSecondsByStep['concert-bb'];
    await page.waitForTimeout(1_200);
    expect((await workspaceSnapshot(page)).elapsedSecondsByStep['concert-bb']).toBe(pausedAt);
    await page.evaluate(() => {
      (window as typeof window & { __setPracticeHidden: (hidden: boolean) => void }).__setPracticeHidden(false);
    });

    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page).toHaveURL(/practice\/scorer\?exercise=cmaj/);
    await expect(page.getByRole('heading', { name: 'Practice Scorer' })).toBeVisible();
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Complete step' }).click();
    await expect(page.getByRole('button', { name: 'Step complete' })).toBeDisabled();

    const completed = await workspaceSnapshot(page);
    expect(completed).toMatchObject({
      packId: 'daily-foundations',
      stepIndex: 2,
      completedStepIds: ['guided-5', 'concert-bb', 'cmaj'],
    });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('button', { name: 'Step complete' })).toBeDisabled();
    const reloaded = await workspaceSnapshot(page);
    expect(reloaded).toMatchObject({
      packId: completed.packId,
      stepIndex: completed.stepIndex,
      completedStepIds: completed.completedStepIds,
    });
    expect(reloaded.elapsedSecondsByStep.cmaj).toBeGreaterThanOrEqual(completed.elapsedSecondsByStep.cmaj);
  } finally {
    await context.setOffline(false);
  }
});

test('the steady-time pack runs its metronome and scorer blocks without network access', async ({ page, context }) => {
  await waitForInstalledShell(page);
  await page.getByRole('button', { name: 'Start pack' }).nth(1).click();
  await expect(page).toHaveURL(/metronome\?bpm=80/);
  await context.setOffline(true);
  try {
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
    await page.evaluate(() => {
      (window as typeof window & { __setPracticeHidden: (hidden: boolean) => void }).__setPracticeHidden(true);
    });
    await expect(page.getByRole('button', { name: 'Start', exact: true })).toBeVisible();
    const pausedAt = (await workspaceSnapshot(page)).elapsedSecondsByStep['steady-80'];
    await page.waitForTimeout(1_200);
    expect((await workspaceSnapshot(page)).elapsedSecondsByStep['steady-80']).toBe(pausedAt);
    await page.evaluate(() => {
      (window as typeof window & { __setPracticeHidden: (hidden: boolean) => void }).__setPracticeHidden(false);
    });
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await expect(page).toHaveURL(/practice\/scorer\?exercise=longtones/);
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expect(page.getByRole('button', { name: 'Stop', exact: true })).toBeVisible();
  } finally {
    await context.setOffline(false);
  }
});
