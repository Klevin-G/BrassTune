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
    ['/', /Tune up, play along, and see how you sound/i],
    ['/practice', /Live mic/i],
    ['/practice/play-along', /Play-Along/i],
    ['/metronome', /Metronome/i],
    ['/practice/score', /Sheet Music/i],
    ['/sessions', /Your recordings/i],
    ['/progress', /Your progress/i],
    ['/ensemble', /Class/i],
    ['/settings', /Settings/i],
    ['/auth/sign-in', /Welcome back/i],
    ['/auth/sign-up', /Create your free BrassTune account/i],
    ['/privacy', /Privacy/i],
    ['/terms', /Terms of Service/i],
    ['/support', /Need help|Support/i],
  ] as const;

  for (const [route, text] of routes) {
    await page.goto(route);
    await expect(page).toHaveURL(new RegExp(`${route === '/' ? '/?$' : route.replace('/', '\\/')}`));
    await expect(page.getByRole('main').getByText(text).first()).toBeVisible();
    await expect(page.locator('.content')).toBeVisible();
    await expect(page.locator('body')).not.toContainText(/Supabase env vars|FastAPI|Start the FastAPI server|Authentication required|cockpit|Practice cockpit/i);
  }
});

test('merged and retired routes redirect to their new home', async ({ page }) => {
  for (const [from, expected] of [
    ['/home', /\/practice$/],
    ['/analytics', /\/progress$/],
    ['/coach', /\/progress$/],
    ['/more', /\/settings$/],
  ] as const) {
    await page.goto(from);
    await expect(page).toHaveURL(expected);
  }
});

test('guest class route invites sign-in without exposing director controls', async ({ page }) => {
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: /sign in to see your class/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Print report|Roster admin|Section trends|Top problem notes|Add student by username/i);
});

test('accounts-unavailable routes still offer guest practice', async ({ page }) => {
  await page.goto('/auth/reset-password');
  await expect(page.getByText(/accounts aren't turned on yet/i)).toBeVisible();
  await expect(page.getByRole('link', { name: /continue as guest|start practicing|keep practicing/i }).first()).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Supabase|VITE_SUPABASE|env vars/i);
});

test('root gateway starts a guest practice session on the tuner', async ({ page }) => {
  await page.addInitScript(() => localStorage.removeItem('brasstune.guestAccess'));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /tune up, play along/i })).toBeVisible();
  // The appearance/theme picker must NOT be on the landing page.
  await expect(page.locator('body')).not.toContainText(/Appearance|Liquid|High Contrast/i);
  await page.getByRole('button', { name: /start practicing/i }).first().click();
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByText(/Live mic/i)).toBeVisible();
});

test('settings replays the tour with a keyboard-trapped dialog', async ({ page }) => {
  await page.goto('/settings');
  await page.getByRole('button', { name: /replay tour/i }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(page.getByRole('button', { name: /close for now/i })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
});

test('demo take creates a reviewable session with a plain-language result', async ({ page }) => {
  await page.goto('/practice');
  const demoMode = page.getByRole('radio', { name: 'Demo', exact: true });
  await demoMode.click();
  await expect(demoMode).toBeChecked();
  const startButton = page.getByRole('button', { name: /save this take/i });
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
  const stopButton = page.getByRole('button', { name: /stop and save/i });
  await expect(stopButton).toBeVisible({ timeout: 30_000 });
  await expect.poll(async () => page.getByRole('timer').textContent(), { timeout: 12_000 }).toMatch(/0:0[2-9]/);
  await stopButton.click();
  const reviewLink = page.getByRole('link', { name: /see results/i });
  await expect(reviewLink).toBeVisible({ timeout: 20_000 });
  await expect(reviewLink).toHaveAttribute('href', /\/sessions\/-/);
  expect(backendSessionCalls).toEqual([]);
  await reviewLink.click();
  await expect(page).toHaveURL(/\/sessions\/-/);
  await expect(page.getByRole('heading', { name: /how each note went/i })).toBeVisible();
  await expect(page.getByText(/in tune/i).first()).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Authentication required/i);
});

test('short mobile tuner controls stay clear of the bottom navigation', async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: () => Promise.reject(new DOMException('Permission denied', 'NotAllowedError')),
      },
    });
  });
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 540, height: 720 },
    { width: 641, height: 720 },
    { width: 860, height: 780 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto('/practice');
    await page.getByRole('radio', { name: /live mic/i }).click();
    await expect(page.locator('.tuner-banner')).toBeVisible();
    await expect(page.locator('.note-display')).toHaveAttribute('aria-label', 'Play a note');
    const controls = page.locator('.tuner-stage .session-controls');
    const bottomNav = page.locator('.floating-tabbar');
    await expect(controls).toBeVisible();
    await expect(bottomNav).toBeVisible();
    const controlsBox = await controls.boundingBox();
    const navBox = await bottomNav.boundingBox();
    expect(controlsBox).not.toBeNull();
    expect(navBox).not.toBeNull();
    expect(
      controlsBox!.y + controlsBox!.height,
      `${viewport.width}x${viewport.height} controls should clear the bottom navigation`,
    ).toBeLessThanOrEqual(navBox!.y + 1);
  }
});

test('tiny-phone empty-state actions stay clear of the bottom navigation', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  for (const [route, actionName] of [
    ['/progress', /record your first note/i],
    ['/sessions', /start practicing/i],
  ] as const) {
    await page.goto(route);
    const action = page.getByRole('link', { name: actionName });
    const bottomNav = page.locator('.floating-tabbar');
    await expect(action).toBeVisible();
    await expect(bottomNav).toBeVisible();
    const actionBox = await action.boundingBox();
    const navBox = await bottomNav.boundingBox();
    expect(actionBox).not.toBeNull();
    expect(navBox).not.toBeNull();
    expect(actionBox!.y + actionBox!.height, `${route} action should clear the bottom navigation`).toBeLessThanOrEqual(navBox!.y + 1);
    const actionIsTopmostAtCenter = await action.evaluate((element) => {
      const rect = element.getBoundingClientRect();
      const topmost = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
      return Boolean(topmost && (topmost === element || element.contains(topmost)));
    });
    expect(actionIsTopmostAtCenter, `${route} action center should remain actionable`).toBe(true);
  }
});

test('narrow settings controls do not widen the document', async ({ page }) => {
  for (const viewport of [
    { width: 320, height: 568 },
    { width: 360, height: 740 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto('/settings');
    await expect(page.getByRole('heading', { name: /settings/i })).toBeVisible();
    const overflow = await page.evaluate(() => (
      Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - document.documentElement.clientWidth
    ));
    expect(overflow, `${viewport.width}px Settings should not overflow horizontally`).toBeLessThanOrEqual(2);
  }
});

test('settings exposes export, danger zone, and legal links', async ({ page }) => {
  await page.goto('/settings');
  await expect(page.getByRole('link', { name: /privacy/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /terms/i })).toBeVisible();
  await expect(page.getByRole('link', { name: /support/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /replay tour/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Open Audio Lab|Practice cockpit|Beta limitations/i);
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

test('a manager cannot force-activate an invited student (consent gate)', async ({ request }) => {
  const created = await request.post(`${apiBaseURL}/api/ensemble/groups`, {
    headers: { Authorization: 'Bearer dev-user-1' },
    data: { name: 'E2E Consent Class' },
  });
  expect(created.status()).toBe(200);
  const group = await created.json();
  const invite = await request.post(`${apiBaseURL}/api/ensemble/groups/${group.id}/members/by-username`, {
    headers: { Authorization: 'Bearer dev-user-1' },
    data: { username: 'maya' },
  });
  expect(invite.status()).toBe(200);
  const member = await invite.json();
  const forced = await request.patch(`${apiBaseURL}/api/ensemble/groups/${group.id}/members/${member.id}`, {
    headers: { Authorization: 'Bearer dev-user-1' },
    data: { status: 'active' },
  });
  expect(forced.status()).toBe(409);
});
