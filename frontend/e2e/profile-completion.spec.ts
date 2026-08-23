import { expect, test, type Page, type Route } from 'playwright/test';

const authModule = `
let subject = 'subject-a';
let listener;
const session = () => ({ access_token: subject + '-token', user: { id: subject } });
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = { auth: {
  getSession: async () => ({ data: { session: session() } }),
  onAuthStateChange: (callback) => { listener = callback; return { data: { subscription: { unsubscribe() {} } } }; },
  signOut: async () => ({ error: null }),
  signInWithPassword: async () => ({ data: { session: session() }, error: null }),
  signUp: async () => ({ data: { session: session() }, error: null }),
} };
window.__switchProfileSubject = (next) => { subject = next; listener?.('SIGNED_IN', session()); };
`;

const confirmationSignupAuthModule = `
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = { auth: {
  getSession: async () => ({ data: { session: null } }),
  onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
  signOut: async () => ({ error: null }),
  signUp: async () => ({ data: { user: { id: 'subject-a' }, session: null }, error: null }),
} };
`;

type Profile = {
  id: number;
  supabase_user_id: string;
  username: string;
  display_name: string;
  email: string;
  role: string;
  primary_instrument_id: string;
  onboarding_completed_at: string;
  profile_complete: boolean;
};

const profileFor = (subject: string, complete = false): Profile => ({
  id: subject === 'subject-b' ? 22 : 11,
  supabase_user_id: subject,
  username: subject === 'subject-b' ? 'player_b' : 'Player_A',
  display_name: subject === 'subject-b' ? 'Player B' : 'Player A',
  email: `${subject}@example.test`,
  role: 'student',
  primary_instrument_id: 'trumpet',
  onboarding_completed_at: '2026-08-23T12:00:00.000Z',
  profile_complete: complete,
});

function json(route: Route, body: unknown, status = 200) {
  return route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
}

async function installAuth(page: Page) {
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: authModule,
  }));
}

async function installConfirmationSignupAuth(page: Page) {
  await page.route('**/src/lib/supabase.ts*', (route) => route.fulfill({
    status: 200,
    contentType: 'application/javascript',
    body: confirmationSignupAuthModule,
  }));
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    Object.keys(localStorage).filter((key) => key.startsWith('brasstune.')).forEach((key) => localStorage.removeItem(key));
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
  });
});

test('explicit email signup fields are completed with both fields and the session token', async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.explicitSignupProfile.v1.subject-a', JSON.stringify({ createdAt: Date.now() }));
  });
  await installAuth(page);
  const patches: Array<{ authorization: string | null; payload: unknown }> = [];
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, profileFor('subject-a'));
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      patches.push({ authorization: route.request().headers().authorization ?? null, payload: route.request().postDataJSON() });
      return json(route, profileFor('subject-a', true));
    }
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/settings');
  await expect.poll(() => patches.length).toBeGreaterThan(0);
  expect(patches[0]).toEqual({
    authorization: 'Bearer subject-a-token',
    payload: { username: 'player_a', display_name: 'Player A' },
  });
  await expect(page.getByRole('button', { name: 'Retry profile setup' })).toHaveCount(0);
});

test('valid provider metadata remains incomplete until the player confirms it', async ({ page }) => {
  await installAuth(page);
  let patchCalls = 0;
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, profileFor('subject-a'));
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      patchCalls += 1;
      return json(route, profileFor('subject-a', true));
    }
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/settings');
  await expect(page.getByRole('heading', { name: 'Finish setting up your profile' })).toBeVisible();
  await expect.poll(() => patchCalls).toBe(0);
  await page.getByRole('button', { name: 'Save profile' }).click();
  await expect.poll(() => patchCalls).toBe(1);
});

test('an incomplete authenticated profile is gated from direct and callback practice navigation', async ({ page }) => {
  await installAuth(page);
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, profileFor('subject-a'));
    return json(route, { detail: 'not found' }, 404);
  });
  await page.goto('/practice?source=direct');
  await expect(page).toHaveURL(/\/settings\?profileCompletion=1&next=%2Fpractice%3Fsource%3Ddirect/);
  await expect(page.getByRole('heading', { name: 'Finish setting up your profile' })).toBeVisible();

  await page.goto('/auth/callback?next=%2Fpractice');
  await expect(page).toHaveURL(/\/settings\?profileCompletion=1&next=%2Fpractice/);
  await expect(page.getByRole('heading', { name: 'Finish setting up your profile' })).toBeVisible();
});

test('confirmation-required email signup completes after the confirmation opens in a new page', async ({ page }) => {
  await installConfirmationSignupAuth(page);
  await page.goto('/auth/sign-up');
  await page.getByRole('textbox', { name: 'Email' }).fill('new@example.test');
  await page.locator('input[name="new-password"]').fill('password123');
  await page.getByRole('textbox', { name: 'Username' }).fill('player_a');
  await page.getByRole('textbox', { name: 'Display name' }).fill('Player A');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByText(/we sent a confirmation link/i)).toBeVisible();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.explicitSignupProfile.v1.subject-a'))).not.toBeNull();

  const callbackPage = await page.context().newPage();
  await installAuth(callbackPage);
  let patchCalls = 0;
  await callbackPage.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, profileFor('subject-a'));
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      patchCalls += 1;
      return json(route, profileFor('subject-a', true));
    }
    return json(route, { detail: 'not found' }, 404);
  });
  await callbackPage.goto('/settings');
  await expect.poll(() => patchCalls).toBeGreaterThan(0);
  await expect.poll(() => callbackPage.evaluate(() => localStorage.getItem('brasstune.explicitSignupProfile.v1.subject-a'))).toBeNull();
  await callbackPage.close();
});

for (const firstFailure of [422, 503]) {
  test(`profile completion keeps auth usable and retries after ${firstFailure}`, async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('brasstune.explicitSignupProfile.v1.subject-a', JSON.stringify({ createdAt: Date.now() }));
    });
    await installAuth(page);
    let patchCalls = 0;
    await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
      const path = new URL(route.request().url()).pathname;
      if (path === '/api/instruments') return json(route, []);
      if (path === '/api/users/current') return json(route, profileFor('subject-a'));
      if (path === '/api/users/me' && route.request().method() === 'PATCH') {
        patchCalls += 1;
        // React StrictMode remounts the provider in this development harness.
        // Fail each mount's automatic attempt so only the explicit retry can
        // resolve the completion state.
        return patchCalls <= 2
          ? json(route, { detail: firstFailure === 422 ? 'Username may contain letters only.' : 'try again later' }, firstFailure)
          : json(route, profileFor('subject-a', true));
      }
      return json(route, { detail: 'not found' }, 404);
    });

    await page.goto('/settings');
    await expect(page.getByText(/account is signed in, but we could not finish profile setup/i)).toBeVisible();
    await expect(page.getByText('Player A')).toBeVisible();
    await expect.poll(() => patchCalls).toBe(2);
    await page.getByRole('button', { name: 'Retry profile setup' }).click();
    await expect.poll(() => patchCalls).toBe(3);
    await expect(page.getByRole('button', { name: 'Retry profile setup' })).toHaveCount(0);
  });
}

test('a stale completion response cannot overwrite a switched account profile', async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.explicitSignupProfile.v1.subject-a', JSON.stringify({ createdAt: Date.now() }));
  });
  await installAuth(page);
  let releaseFirstPatch: (() => void) | undefined;
  const firstPatchReleased = new Promise<void>((resolve) => { releaseFirstPatch = resolve; });
  let firstPatchStarted: (() => void) | undefined;
  const firstPatchSeen = new Promise<void>((resolve) => { firstPatchStarted = resolve; });
  await page.route(/^https?:\/\/[^/]+\/api\//, async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') {
      const authorization = route.request().headers().authorization;
      return json(route, authorization === 'Bearer subject-b-token' ? profileFor('subject-b', true) : profileFor('subject-a'));
    }
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      firstPatchStarted?.();
      await firstPatchReleased;
      return json(route, profileFor('subject-a', true));
    }
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/settings');
  await firstPatchSeen;
  await page.evaluate(() => (window as typeof window & { __switchProfileSubject: (subject: string) => void }).__switchProfileSubject('subject-b'));
  await expect(page.getByText('Player B')).toBeVisible();
  releaseFirstPatch?.();
  await page.waitForTimeout(100);
  await expect(page.getByText('Player B')).toBeVisible();
  await expect(page.getByText('Player A')).toHaveCount(0);
});

test('an OAuth or legacy profile missing required fields can complete them in Spanish', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('brasstune.locale', 'es'));
  await installAuth(page);
  const legacyProfile = { ...profileFor('subject-a'), username: null, display_name: '', profile_complete: false };
  const patches: unknown[] = [];
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, legacyProfile);
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      patches.push(route.request().postDataJSON());
      return json(route, { ...legacyProfile, username: 'maria_1', display_name: 'María', profile_complete: true });
    }
    return json(route, { detail: 'not found' }, 404);
  });

  await page.goto('/settings');
  await expect(page.getByRole('heading', { name: 'Termina de configurar tu perfil' })).toBeVisible();
  await page.getByRole('textbox', { name: 'Nombre de usuario' }).fill('maria_1');
  await page.getByRole('textbox', { name: 'Nombre para mostrar' }).fill('María');
  await page.getByRole('button', { name: 'Guardar perfil' }).click();
  await expect.poll(() => patches).toEqual([{ username: 'maria_1', display_name: 'María' }]);
  await expect(page.getByRole('heading', { name: 'Termina de configurar tu perfil' })).toHaveCount(0);
});

test('profile completion accepts an 80-character display name and rejects 81 characters', async ({ page }) => {
  await installAuth(page);
  const legacyProfile = { ...profileFor('subject-a'), username: null, display_name: '', profile_complete: false };
  let patchCalls = 0;
  await page.route(/^https?:\/\/[^/]+\/api\//, (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === '/api/instruments') return json(route, []);
    if (path === '/api/users/current') return json(route, legacyProfile);
    if (path === '/api/users/me' && route.request().method() === 'PATCH') {
      patchCalls += 1;
      return json(route, { ...legacyProfile, username: 'player_80', display_name: 'a'.repeat(80), profile_complete: true });
    }
    return json(route, { detail: 'not found' }, 404);
  });
  await page.goto('/settings');
  await page.getByRole('textbox', { name: 'Username' }).fill('player_80');
  const displayName = page.getByRole('textbox', { name: 'Display name' });
  await displayName.evaluate((input) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    setter?.call(input, 'a'.repeat(81));
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await page.getByRole('button', { name: 'Save profile' }).click();
  await expect(page.getByRole('alert')).toHaveText('Enter a display name of up to 80 characters.');
  expect(patchCalls).toBe(0);
  await displayName.fill('a'.repeat(80));
  await page.getByRole('button', { name: 'Save profile' }).click();
  await expect.poll(() => patchCalls).toBe(1);
});
