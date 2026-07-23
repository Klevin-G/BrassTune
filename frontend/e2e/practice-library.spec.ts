import { expect, test, type Route } from 'playwright/test';

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

test('Arabic tiny-phone tuner fits the viewport while keeping the pitch axis left-to-right', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('brasstune.locale', 'ar'));
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/practice');
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.locator('.tuner-stage')).toBeVisible();

  const layout = await page.evaluate(() => ({
    clientWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth,
    meterDirection: getComputedStyle(document.querySelector('.tuning-meter-track') as HTMLElement).direction,
  }));
  expect(layout.scrollWidth).toBeLessThanOrEqual(layout.clientWidth);
  expect(layout.meterDirection).toBe('ltr');
});

test('weekly goal drafts resync after guest hydration and an account owner switch', async ({ page }) => {
  await page.addInitScript(() => {
    const library = (owner: string, targetMinutes: number, targetSessions: number) => JSON.stringify({
      version: 1,
      customExercises: [{ id: `exercise-${owner}`, name: `${owner} lip slur`, notes: ['C', 'G'], source: 'custom', createdAt: '2026-07-22T12:00:00.000Z' }],
      metronomePresets: [],
      favorites: [{ kind: 'warmup', id: `favorite-${owner}`, label: `${owner} favorite`, href: '/practice' }],
      recents: [{ kind: 'warmup', id: `recent-${owner}`, label: `${owner} recent`, href: '/practice' }],
      reflections: [{ id: `reflection-${owner}`, text: `${owner} reflection`, createdAt: '2026-07-22T12:00:00.000Z' }],
      warmup: { elapsedSeconds: owner === 'owner-99' ? 37 : 81, stepIndex: 1, updatedAt: '2026-07-22T12:00:00.000Z' },
      weeklyGoal: { week: '2026-07-20', targetMinutes, completedMinutes: 0, targetSessions, completedSessions: 0 },
    });
    localStorage.setItem('brasstune.practiceLibrary.v1.account%3A99', library('owner-99', 77, 4));
    localStorage.setItem('brasstune.practiceLibrary.v1.account%3A100', library('owner-100', 123, 6));
  });

  const authModule = `
let session = { access_token: 'owner-99', user: { id: 'auth-99' } };
const listeners = [];
window.__switchPracticeOwner = (owner = 100) => {
  session = owner === 99
    ? { access_token: 'owner-99', user: { id: 'auth-99' } }
    : { access_token: 'owner-100', user: { id: 'auth-100' } };
  listeners.forEach((listener) => listener('SIGNED_IN', session));
};
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = { auth: {
  getSession: async () => ({ data: { session } }),
  onAuthStateChange: (listener) => { listeners.push(listener); return { data: { subscription: { unsubscribe() {} } } }; },
  signOut: async () => ({ error: null }),
} };
`;
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({ status: 200, contentType: 'application/javascript', body: authModule }));
  await page.route(/^https?:\/\/[^/]+\/api\//, async (route: Route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/users/current') {
      const secondOwner = route.request().headers().authorization?.includes('owner-100');
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          id: secondOwner ? 100 : 99,
          supabase_user_id: secondOwner ? 'auth-100' : 'auth-99',
          username: secondOwner ? 'second-owner' : 'first-owner',
          display_name: secondOwner ? 'Second Owner' : 'First Owner',
          email: secondOwner ? 'second@example.test' : 'first@example.test',
          role: 'student',
          primary_instrument_id: 'trumpet',
          onboarding_completed_at: '2026-07-22T12:00:00.000Z',
        }),
      });
    }
    if (path === '/api/instruments') return route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
    return route.fulfill({ status: 404, contentType: 'application/json', body: '{"detail":"Not found"}' });
  });

  await page.goto('/practice');
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('77');
  await expect(page.getByLabel('Goal in sessions')).toHaveValue('4');
  const owner99State = await page.evaluate(() => JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.account%3A99') ?? '{}'));
  const owner99Expected = {
    customExercises: [{ name: 'owner-99 lip slur', notes: ['C', 'G'] }],
    favorites: [{ id: 'favorite-owner-99' }],
    recents: [{ id: 'recent-owner-99' }],
    reflections: [{ text: 'owner-99 reflection' }],
    warmup: { elapsedSeconds: 37 },
    weeklyGoal: { targetMinutes: 77, targetSessions: 4 },
  };
  expect(owner99State).toMatchObject(owner99Expected);
  await page.evaluate(() => (window as unknown as { __switchPracticeOwner: (owner?: number) => void }).__switchPracticeOwner(100));
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('123');
  await expect(page.getByLabel('Goal in sessions')).toHaveValue('6');
  const owner100AfterSwitch = await page.evaluate(() => localStorage.getItem('brasstune.practiceLibrary.v1.account%3A100'));
  expect(owner100AfterSwitch).toContain('owner-100 lip slur');
  expect(owner100AfterSwitch).toContain('"elapsedSeconds":81');
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.account%3A99') ?? '{}'))).toMatchObject(owner99Expected);

  await page.getByLabel('Goal in minutes').fill('144');
  await page.getByRole('button', { name: 'Save goal' }).click();
  await page.evaluate(() => (window as unknown as { __switchPracticeOwner: (owner?: number) => void }).__switchPracticeOwner(99));
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('77');
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.account%3A99') ?? '{}'))).toMatchObject(owner99Expected);
  expect(await page.evaluate(() => localStorage.getItem('brasstune.practiceLibrary.v1.account%3A100'))).toContain('"targetMinutes":144');
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

test('a failed locale chunk atomically falls back to English and can retry', async ({ page }) => {
  let failArabicChunk = true;
  await page.route('**/src/i18n/catalogs/locale-ar.ts*', (route) => {
    if (failArabicChunk) return route.abort('failed');
    return route.continue();
  });

  await page.goto('/settings');
  await page.getByLabel('App language').selectOption('ar');
  await expect(page.getByRole('alert')).toContainText('switched back to English');
  await expect(page.getByLabel('App language')).toHaveValue('en');
  await expect(page.locator('html')).toHaveAttribute('lang', 'en');
  await expect(page.locator('html')).toHaveAttribute('dir', 'ltr');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.locale'))).toBe('en');

  failArabicChunk = false;
  await page.getByRole('button', { name: 'Retry language download' }).click();
  await expect(page.locator('html')).toHaveAttribute('lang', 'ar');
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.getByLabel('لغة التطبيق')).toHaveValue('ar');
  await expect(page.getByRole('alert')).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.locale'))).toBe('ar');
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
