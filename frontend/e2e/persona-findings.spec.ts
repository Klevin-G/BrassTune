import { expect, test, type Page, type Route } from 'playwright/test';
import AxeBuilder from '@axe-core/playwright';

const accountAuthModule = `
const subject = localStorage.getItem('e2e.authSubject') || 'verified-subject';
const session = { access_token: subject, user: { id: subject } };
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = { auth: {
  getSession: async () => ({ data: { session } }),
  onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
  signOut: async () => ({ error: null }),
  signInWithPassword: async () => ({ data: { session }, error: null }),
  signUp: async () => ({ data: { session }, error: null }),
} };
`;

const signedOutAuthModule = `
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = { auth: {
  getSession: async () => ({ data: { session: null } }),
  onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
  signOut: async () => ({ error: null }),
  signInWithPassword: async () => ({ data: { session: null }, error: new Error('network request failed') }),
} };
`;

const oauthAuthModule = `
export const supabaseConfigured = true;
export const authProviders = { google: true, apple: true };
export const supabase = { auth: {
  getSession: async () => ({ data: { session: null } }),
  onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
  signOut: async () => ({ error: null }),
  signInWithPassword: async () => ({ data: { session: null }, error: null }),
  signInWithOAuth: async (credentials) => {
    localStorage.setItem('e2e.oauthCredentials', JSON.stringify(credentials));
    await new Promise((resolve) => setTimeout(resolve, 180));
    return localStorage.getItem('e2e.oauthFailure') === 'true'
      ? { data: {}, error: new Error('network request failed') }
      : { data: { url: 'https://provider.example/authorize' }, error: null };
  },
} };
`;

const unconfiguredAuthModule = `
export const supabaseConfigured = false;
export const authProviders = { google: false, apple: false };
export const supabase = null;
`;

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
}

async function routeAuthModule(page: Page, body: string) {
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body,
  }));
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    if (sessionStorage.getItem('e2e.personaFindings.initialized') === 'true') return;
    Object.keys(localStorage).filter((key) => key.startsWith('brasstune.')).forEach((key) => localStorage.removeItem(key));
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    sessionStorage.setItem('e2e.personaFindings.initialized', 'true');
  });
});

test('an exact verified account keeps local practice during profile outage without cross-account inheritance', async ({ page }) => {
  let profileAvailable = true;
  await routeAuthModule(page, accountAuthModule);
  await page.addInitScript(() => {
    if (localStorage.getItem('e2e.authSubject')) return;
    localStorage.setItem('e2e.authSubject', 'verified-subject');
    localStorage.setItem('brasstune.practiceLibrary.v1.account%3A99', JSON.stringify({
      version: 1,
      customExercises: [],
      metronomePresets: [],
      favorites: [],
      recents: [],
      reflections: [],
      warmup: { elapsedSeconds: 0, stepIndex: 0, updatedAt: '2026-07-23T12:00:00Z' },
      weeklyGoal: { week: '2026-07-20', targetMinutes: 91, completedMinutes: 0, targetSessions: 4, completedSessions: 0 },
    }));
  });
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/users/current' && profileAvailable) {
      return json(route, {
        id: 99,
        supabase_user_id: 'verified-subject',
        username: 'verified',
        display_name: 'Verified Player',
        email: 'verified@example.test',
        role: 'student',
        primary_instrument_id: 'trumpet',
        onboarding_completed_at: '2026-07-23T12:00:00Z',
      });
    }
    if (path === '/api/users/current') return json(route, { detail: 'offline' }, 503);
    if (path === '/api/instruments') return json(route, []);
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/practice');
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('91');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.verifiedPracticeNamespace.v1.verified-subject'))).not.toBeNull();

  profileAvailable = false;
  await page.reload();
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('91');
  await expect(page.getByText('We could not finish restoring your account')).toHaveCount(0);

  await page.evaluate(() => localStorage.setItem('e2e.authSubject', 'different-subject'));
  await page.reload();
  await expect(page.getByRole('heading', { name: 'We could not finish restoring your account' })).toBeVisible();
  await expect(page.getByLabel('Goal in minutes')).toHaveCount(0);
});

test('focused pack completion stops elapsed time and records weekly activity once', async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
  await page.goto('/practice');
  await page.getByRole('button', { name: 'Start pack' }).first().click();
  await page.waitForTimeout(1_100);
  await page.getByRole('button', { name: /Next/ }).click();
  await page.getByRole('button', { name: /Next/ }).click();
  await page.getByRole('button', { name: 'Complete step' }).click();

  const completed = await page.evaluate(() => ({
    library: JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.guest') ?? '{}'),
    workspace: JSON.parse(sessionStorage.getItem('brasstune.practiceWorkspace.v1.guest') ?? '{}'),
  }));
  expect(completed.library.weeklyGoal).toMatchObject({ completedMinutes: 1, completedSessions: 1 });
  const elapsedAtCompletion = completed.workspace.elapsedSecondsByStep;
  await page.waitForTimeout(1_200);
  const after = await page.evaluate(() => ({
    library: JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.guest') ?? '{}'),
    workspace: JSON.parse(sessionStorage.getItem('brasstune.practiceWorkspace.v1.guest') ?? '{}'),
  }));
  expect(after.library.weeklyGoal).toMatchObject({ completedMinutes: 1, completedSessions: 1 });
  expect(after.workspace.elapsedSecondsByStep).toEqual(elapsedAtCompletion);
});

test('a real Play-Along pack step owns weekly activity so final pack completion does not double-count', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('brasstune.guestAccess', 'true'));
  await page.route('**/src/hooks/usePitchStream.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: `
export function usePitchStream() {
  return {
    micActive: true,
    statusMessage: '',
    streamInfo: { audioContextState: 'running' },
    startMicrophone: async () => true,
    stopMicrophone() {},
  };
}
`,
  }));

  await page.goto('/practice');
  await page.getByRole('button', { name: 'Start pack' }).first().click();
  await page.getByRole('button', { name: /Next/ }).click();
  await page.getByRole('button', { name: /Next/ }).click();
  await expect(page).toHaveURL(/\/practice\/scorer\?exercise=cmaj/);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  const skip = page.getByRole('button', { name: 'Skip note' });
  for (let index = 0; index < 8; index += 1) await skip.click();

  await expect.poll(() => page.evaluate(() => {
    const library = JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.guest') ?? '{}');
    return library.weeklyGoal;
  })).toMatchObject({ completedMinutes: 1, completedSessions: 1 });
  await page.getByRole('button', { name: 'Complete step' }).click();
  await expect.poll(() => page.evaluate(() => {
    const library = JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.guest') ?? '{}');
    return library.weeklyGoal;
  })).toMatchObject({ completedMinutes: 1, completedSessions: 1 });
  await expect.poll(() => page.evaluate(() => {
    const workspace = JSON.parse(sessionStorage.getItem('brasstune.practiceWorkspace.v1.guest') ?? '{}');
    return workspace.activityRecordedStepIds;
  })).toEqual(['cmaj']);
});

test('session review filters reflections and guest deletion detaches only the matching note', async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.guestAccess', 'true');
    const session = (id: number, name: string) => ({
      id,
      user_id: 0,
      instrument_id: 'trumpet',
      name,
      started_at: '2026-07-23T12:00:00Z',
      ended_at: '2026-07-23T12:01:00Z',
      created_at: '2026-07-23T12:00:00Z',
      duration_seconds: 60,
      reference_pitch_hz: 440,
      notes_count: 0,
      average_signed_cents: 0,
      average_abs_cents: 0,
      in_tune_percentage: 0,
      audio_available: false,
      guest_session: true,
      samples_count: 0,
      note_events: [],
      note_stats: [],
      heatmap: [],
      recommendations: [],
      frames: [],
    });
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([
      session(-101, 'First take'),
      session(-202, 'Second take'),
    ]));
    localStorage.setItem('brasstune.practiceLibrary.v1.guest', JSON.stringify({
      version: 1,
      customExercises: [],
      metronomePresets: [],
      favorites: [],
      recents: [],
      reflections: [
        { id: 'first', text: 'Reflection for first take', createdAt: '2026-07-23T12:00:00Z', sessionId: '-101' },
        { id: 'second', text: 'Reflection for second take', createdAt: '2026-07-23T12:00:00Z', sessionId: '-202' },
        { id: 'general', text: 'General reflection', createdAt: '2026-07-23T12:00:00Z' },
      ],
      warmup: { elapsedSeconds: 0, stepIndex: 0, updatedAt: '2026-07-23T12:00:00Z' },
      weeklyGoal: { week: '2026-07-20', targetMinutes: 60, completedMinutes: 0, targetSessions: 3, completedSessions: 0 },
    }));
  });

  await page.goto('/sessions/-101');
  await expect(page.getByText('Reflection for first take')).toBeVisible();
  await expect(page.getByText('Reflection for second take')).toHaveCount(0);
  await expect(page.getByText('General reflection')).toHaveCount(0);

  await page.goto('/sessions');
  await page.locator('a[href="/sessions/-101"]').locator('..').locator('summary').click();
  await page.getByRole('button', { name: 'Delete recording' }).click();
  await page.getByRole('button', { name: 'Delete', exact: true }).click();
  await expect(page.getByText('First take')).toHaveCount(0);
  const reflections = await page.evaluate(() => JSON.parse(localStorage.getItem('brasstune.practiceLibrary.v1.guest') ?? '{}').reflections);
  expect(reflections).toEqual([
    { id: 'first', text: 'Reflection for first take', createdAt: '2026-07-23T12:00:00Z' },
    { id: 'second', text: 'Reflection for second take', createdAt: '2026-07-23T12:00:00Z', sessionId: '-202' },
    { id: 'general', text: 'General reflection', createdAt: '2026-07-23T12:00:00Z' },
  ]);
});

test('join return and privacy disclosure survive the auth gateway', async ({ page }) => {
  await routeAuthModule(page, signedOutAuthModule);
  await page.addInitScript(() => localStorage.setItem('brasstune.guestAccess', 'true'));
  await page.goto('/ensemble?join=BRASS7');
  const disclosure = page.getByText(/aggregate cloud practice totals/i);
  await expect(disclosure).toBeVisible();
  await expect(disclosure).toContainText('class directors and BrassTune administrators');
  const signIn = page.getByRole('link', { name: 'Sign in or create an account' });
  await expect(signIn).toHaveAttribute('href', '/?next=%2Fensemble%3Fjoin%3DBRASS7');
  await signIn.click();
  await expect(page).toHaveURL(/\/\?next=%2Fensemble%3Fjoin%3DBRASS7$/);
});

test('Google and Apple launch real OAuth actions with an exact callback and recoverable provider states', async ({ page }) => {
  await routeAuthModule(page, oauthAuthModule);
  await page.goto('/auth/sign-in?next=%2Fensemble%3Fjoin%3DBRASS7');

  const google = page.getByRole('button', { name: 'Continue with Google' });
  const apple = page.getByRole('button', { name: 'Continue with Apple' });
  await expect(google).toBeEnabled();
  await expect(apple).toBeEnabled();
  await expect(google.locator('img')).toHaveAttribute('src', /^data:image\/png;base64,/);
  await expect(google.locator('svg')).toHaveCount(0);
  await expect(apple.locator('img')).toHaveAttribute('src', /^data:image\/png;base64,/);

  await google.click();
  await expect(page.getByRole('button', { name: 'Continuing to Google…' })).toBeDisabled();
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('e2e.oauthCredentials') ?? '{}')))
    .toMatchObject({
      provider: 'google',
      options: {
        redirectTo: `${new URL(page.url()).origin}/auth/callback`,
        scopes: 'openid email profile',
        queryParams: { prompt: 'select_account' },
      },
    });
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.pendingAuthNext')))
    .toBe('/ensemble?join=BRASS7');
  await expect(google).toBeEnabled();

  await apple.click();
  await expect(page.getByRole('button', { name: 'Continuing to Apple…' })).toBeDisabled();
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('e2e.oauthCredentials') ?? '{}')))
    .toEqual({
      provider: 'apple',
      options: { redirectTo: `${new URL(page.url()).origin}/auth/callback` },
    });
  await expect(apple).toBeEnabled();

  await page.evaluate(() => localStorage.setItem('e2e.oauthFailure', 'true'));
  await google.click();
  await expect(page.getByRole('alert')).toContainText('Account access could not reach the server');
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.pendingAuthNext'))).toBeNull();
  await expect(page.getByRole('button', { name: 'Keep practicing as a guest' })).toBeEnabled();

  await page.evaluate(() => {
    sessionStorage.setItem('brasstune.pendingAuthNext', '/ensemble?join=STALE7');
    localStorage.removeItem('e2e.oauthFailure');
  });
  await page.goto('/auth/callback#error=access_denied&error_description=User+canceled');
  await expect(page.getByRole('heading', { name: 'Sign-in did not finish' })).toBeVisible();
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.pendingAuthNext'))).toBeNull();
});

test('disabled OAuth providers stay visibly unavailable and RTL auth callback arrows follow reading direction', async ({ page }) => {
  await routeAuthModule(page, signedOutAuthModule);
  await page.goto('/auth/sign-in?next=https%3A%2F%2Fevil.example%2Fsteal');
  await expect(page.getByRole('button', { name: 'Google sign-in unavailable' })).toBeDisabled();
  const unavailableApple = page.getByRole('button', { name: 'Apple sign-in unavailable' });
  await expect(unavailableApple).toBeDisabled();
  await expect(unavailableApple.locator('img, svg')).toHaveCount(0);

  await page.unroute('**/src/lib/supabase.ts*');
  await routeAuthModule(page, unconfiguredAuthModule);
  await page.addInitScript(() => localStorage.setItem('brasstune.locale', 'ar'));
  await page.goto('/auth/callback');
  await expect(page.locator('.au-callback .lucide-arrow-left')).toBeVisible();
  await page.goto('/auth/sign-in');
  await expect(page.getByRole('button', { name: 'استمر كضيف' }).locator('.lucide-arrow-left')).toBeVisible();
  const results = await new AxeBuilder({ page }).include('main').analyze();
  expect(results.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''))).toEqual([]);
});

test('Arabic auth and class surfaces preserve RTL semantics, mixed-direction tokens, and axe gates', async ({ page }) => {
  await routeAuthModule(page, signedOutAuthModule);
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.guestAccess', 'true');
    localStorage.setItem('brasstune.locale', 'ar');
  });
  await page.goto('/ensemble?join=CMAJ7');
  await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
  await expect(page.getByText(/إجمالي تدريبك السحابي/)).toBeVisible();
  await expect(page.getByRole('link', { name: 'تسجيل الدخول أو إنشاء حساب' })).toHaveAttribute(
    'href',
    '/?next=%2Fensemble%3Fjoin%3DCMAJ7',
  );
  let results = await new AxeBuilder({ page }).include('main').analyze();
  expect(results.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''))).toEqual([]);

  await page.getByRole('link', { name: 'تسجيل الدخول أو إنشاء حساب' }).click();
  const guestArrowTransform = await page.locator('.ag-guest svg').first().evaluate((element) => getComputedStyle(element).transform);
  expect(guestArrowTransform).toContain('-1');
  await page.getByRole('button', { name: 'قم بتسجيل الدخول باستخدام البريد الإلكتروني' }).click();
  await expect(page.getByLabel('بريد إلكتروني')).toHaveAttribute('dir', 'ltr');
  await page.getByLabel('بريد إلكتروني').fill('player@example.test');
  await page.getByLabel('كلمة المرور').fill('secret1');
  await page.locator('form').getByRole('button', { name: 'تسجيل الدخول' }).click();
  await expect(page.getByRole('status')).toContainText('تعذّر الاتصال بخادم الحساب');
  results = await new AxeBuilder({ page }).include('main').analyze();
  expect(results.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''))).toEqual([]);

  await page.evaluate(() => localStorage.setItem('brasstune.guestAccess', 'true'));
  await page.goto('/practice/scorer');
  await expect(page.getByRole('button', { name: /سلم C الكبير/ }).first()).toBeVisible();
  await expect(page.getByRole('button', { name: /سلم ج الكبير/ })).toHaveCount(0);
});

test('partial class failures stay unavailable, clipboard failure is manual, and Play-Along exposes a focused score', async ({ page }) => {
  let rotationRequests = 0;
  await routeAuthModule(page, accountAuthModule);
  await page.addInitScript(() => {
    localStorage.setItem('e2e.authSubject', 'verified-subject');
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: async () => { throw new Error('denied'); } },
    });
  });
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/users/current') return json(route, {
      id: 99,
      supabase_user_id: 'verified-subject',
      username: 'director',
      display_name: 'Director',
      email: 'director@example.test',
      role: 'director',
      primary_instrument_id: 'trumpet',
      onboarding_completed_at: '2026-07-23T12:00:00Z',
    });
    if (path === '/api/ensemble/groups') return json(route, [
      { id: 1, name: 'Concert Band', join_code: 'BRASS7', viewer_can_manage: true, viewer_role: 'owner' },
      { id: 2, name: 'Second Band', join_code: 'SECOND8', viewer_can_manage: true, viewer_role: 'owner' },
    ]);
    if (path === '/api/ensemble/groups/1') return json(route, { id: 1, name: 'Concert Band', join_code: 'BRASS7', viewer_can_manage: true, viewer_role: 'owner', members: [] });
    if (path === '/api/ensemble/groups/2') return json(route, { id: 2, name: 'Second Band', join_code: 'SECOND8', viewer_can_manage: true, viewer_role: 'owner', members: [] });
    if (path === '/api/ensemble/groups/2/join-code/rotate') {
      rotationRequests += 1;
      return rotationRequests > 1
        ? json(route, { detail: 'temporarily unavailable' }, 503)
        : json(route, { group_id: 2, join_code: 'FRESH9' });
    }
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/ensemble/invitations' || path === '/api/ensemble/summary' || path === '/api/ensemble/report' || /\/roster$/.test(path)) {
      return json(route, { detail: 'temporarily unavailable' }, 503);
    }
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/ensemble');
  await expect(page.getByText(/Invitations are unavailable/)).toBeVisible();
  await expect(page.getByText(/roster is unavailable/)).toBeVisible();
  await expect(page.getByText(/Section summary is unavailable/)).toBeVisible();
  await expect(page.getByText(/rehearsal report is unavailable/)).toBeVisible();
  await page.getByRole('button', { name: 'Share link' }).click();
  await expect(page.getByText('Copied')).toHaveCount(0);
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveValue(/ensemble\?join=BRASS7/);
  await page.getByRole('button', { name: 'Second Band' }).click();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveCount(0);
  await page.getByRole('button', { name: 'Share link' }).click();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveValue(/ensemble\?join=SECOND8/);

  await page.getByRole('button', { name: 'Rotate code' }).click();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveCount(0);
  await expect(page.getByText('FRESH9')).toBeVisible();
  await page.getByRole('button', { name: 'Share link' }).click();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveValue(/ensemble\?join=FRESH9/);

  await page.getByRole('button', { name: 'Rotate code' }).click();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveCount(0);
  await expect(page.getByText('Cloud practice is unavailable right now. Guest practice still works on this device.')).toBeVisible();

  await page.evaluate(() => Object.defineProperty(navigator, 'clipboard', {
    configurable: true,
    value: { writeText: async () => undefined },
  }));
  await page.getByRole('button', { name: 'Share link' }).click();
  await expect(page.getByText('Copied')).toBeVisible();
  await expect(page.getByLabel(/Clipboard access failed/)).toHaveCount(0);

  await page.route('**/src/hooks/usePitchStream.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: `
export function usePitchStream() {
  return {
    micActive: true,
    statusMessage: '',
    streamInfo: { audioContextState: 'running' },
    startMicrophone: async () => true,
    stopMicrophone() {},
  };
}
`,
  }));
  await page.goto('/practice/scorer');
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  const holdProgress = page.getByRole('progressbar', { name: /Hold C steadily/ });
  await expect(holdProgress).toHaveAttribute('value', '0');
  await expect(holdProgress).toHaveJSProperty('tagName', 'PROGRESS');
  const targetStatus = page.getByRole('status').filter({ hasText: /Target C/ });
  await expect(targetStatus).toHaveJSProperty('tagName', 'OUTPUT');
  const noteList = page.getByRole('list', { name: 'Note by note' });
  await expect(noteList).toHaveJSProperty('tagName', 'OL');
  await expect(noteList.getByRole('listitem')).toHaveCount(8);
  await expect(page.locator('.playalong-note').first()).toHaveAttribute('aria-label', /C, current target/);
  const liveAxe = await new AxeBuilder({ page }).include('main').analyze();
  expect(liveAxe.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''))).toEqual([]);
  const skip = page.getByRole('button', { name: 'Skip note' });
  for (let index = 0; index < 8; index += 1) await skip.click();
  await expect(page.locator('.pa-verdict')).toBeFocused();
  await expect(page.locator('.pa-verdict')).toHaveJSProperty('tagName', 'SECTION');
  const summaryHeight = await page.locator('.pa-details > summary').evaluate((element) => element.getBoundingClientRect().height);
  expect(summaryHeight).toBeGreaterThanOrEqual(44);
  await expect(page.getByText('Show', { exact: true })).toBeVisible();
});
