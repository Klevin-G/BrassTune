import { expect, test } from 'playwright/test';
import type { Page, Response } from 'playwright/test';
import {
  approvedBrassTuneVercelOrigins,
  installScopedVercelBypass,
  scopedVercelBypassHeaders,
} from './vercel-bypass';

const apiBaseURL = process.env.E2E_API_BASE_URL;
const wsBaseURL = process.env.E2E_WS_BASE_URL;
const strictHostedContent = process.env.E2E_STRICT_HOSTED_CONTENT === '1';
const hostedMode = process.env.E2E_START_LOCAL_SERVERS === '0';
const vercelShareURL = process.env.E2E_VERCEL_SHARE_URL;
const vercelBypassSecret = process.env.E2E_VERCEL_AUTOMATION_BYPASS_SECRET || process.env.VERCEL_AUTOMATION_BYPASS_SECRET;
const webBaseURL = process.env.E2E_BASE_URL;
const expectedFrontendSha = process.env.BRASSTUNE_EXPECTED_FRONTEND_SHA?.trim().toLowerCase();
const productionHostedAuth = hostedMode && webBaseURL
  ? new URL(webBaseURL).hostname === 'brasstune.vercel.app'
  : false;
const harmlessBrowserErrors = new Set([
  'ResizeObserver loop completed with undelivered notifications.',
  'ResizeObserver loop limit exceeded',
]);

const routes = [
  '/',
  '/practice',
  '/sessions',
  '/analytics',
  '/progress',
  '/coach',
  '/ensemble',
  '/more',
  '/settings',
  '/settings/audio-lab',
  '/auth/sign-in',
  '/auth/sign-up',
  '/auth/reset-password',
  '/auth/callback#error=access_denied&error_description=User+canceled',
  '/privacy',
  '/terms',
  '/support',
];

const expectedRoutePaths = new Map([
  ['/analytics', '/progress'],
  ['/coach', '/progress'],
  ['/more', '/settings'],
  ['/settings/audio-lab', '/settings'],
]);

function assertNoHostedURLRegression(url: string, appOrigin: string) {
  const parsed = new URL(url);
  const isLocal = ['localhost', '127.0.0.1', '[::1]'].includes(parsed.hostname);
  expect(isLocal, `${url} must not point at localhost in hosted smoke`).toBe(false);
  if (appOrigin.startsWith('https:')) {
    expect(parsed.protocol, `${url} must not use insecure HTTP from an HTTPS app`).not.toBe('http:');
  }
  if (parsed.origin === appOrigin) {
    expect(parsed.pathname, `${url} must not call same-origin API/WS on Vercel`).not.toMatch(/^\/(api|ws)(\/|$)/);
  }
}

function routeURL(route: string) {
  if (!hostedMode || !vercelShareURL) return route;
  const shared = new URL(vercelShareURL);
  const destination = new URL(route, shared.origin);
  const shareToken = shared.searchParams.get('_vercel_share');
  if (shareToken) destination.searchParams.set('_vercel_share', shareToken);
  return destination.toString();
}

const approvedVercelOrigins = approvedBrassTuneVercelOrigins(webBaseURL, vercelShareURL);

async function assertNotProtectedPreview(response: Response | null, page: Page, route: string) {
  if (response?.status() !== 401 && response?.status() !== 403) return;
  const baseHostname = webBaseURL ? new URL(webBaseURL).hostname : '';
  const unauthenticatedVercelPreview = baseHostname.endsWith('.vercel.app') && baseHostname !== 'brasstune.vercel.app' && !vercelShareURL && !vercelBypassSecret;
  if (unauthenticatedVercelPreview) {
    throw new Error(`Protected Vercel preview returned ${response?.status()} for ${route}; provide E2E_VERCEL_SHARE_URL or an automation bypass for page journeys.`);
  }
  const bodyText = await page.locator('body').innerText({ timeout: 5_000 }).catch(() => '');
  if (/vercel authentication|log in to vercel|single sign-on|authentication required/i.test(bodyText)) {
    throw new Error(`Protected Vercel preview blocked ${route}; provide E2E_VERCEL_SHARE_URL or an automation bypass for page journeys.`);
  }
}

async function grantGuestAccess(page: Page) {
  await page.addInitScript(() => {
    window.localStorage.setItem('brasstune.guestAccess', 'true');
  });
}

async function startWithFreshAuthStorage(page: Page) {
  await page.context().clearCookies();
  await page.addInitScript(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
  });
}

test.describe('hosted read-only smoke', () => {
  test.beforeEach(async ({ page }) => {
    if (hostedMode && vercelBypassSecret) {
      await installScopedVercelBypass(page, vercelBypassSecret, approvedVercelOrigins);
    }
  });

  test('Vercel bypass credential is scoped to approved BrassTune page origins', () => {
    const secret = 'test-only-bypass';
    const approved = approvedBrassTuneVercelOrigins(
      'https://brass-tune-123-kelvis-prject.vercel.app/share',
      'https://unrelated.example.test/not-approved',
    );
    const incomingHeaders = {
      Accept: 'text/html',
      'X-Vercel-Protection-Bypass': 'must-be-replaced-or-removed',
    };

    const protectedPage = scopedVercelBypassHeaders(
      'https://brass-tune-123-kelvis-prject.vercel.app/practice',
      incomingHeaders,
      secret,
      approved,
    );
    expect(protectedPage['x-vercel-protection-bypass']).toBe(secret);

    for (const url of [
      'https://brasstune-u8qj.onrender.com/api/ready',
      'https://redirect-target.example.test/after-vercel-redirect',
      'https://cdn.example.test/app.js',
    ]) {
      const headers = scopedVercelBypassHeaders(url, incomingHeaders, secret, approved);
      expect(Object.keys(headers).map((name) => name.toLowerCase())).not.toContain('x-vercel-protection-bypass');
    }
  });

  test('production exposes enabled Google, Apple, and email sign-in from fresh storage', async ({ page }) => {
    test.skip(!productionHostedAuth, 'Canonical production auth is not required for local or preview smoke runs.');
    await startWithFreshAuthStorage(page);

    const rootResponse = await page.goto(routeURL('/'));
    await assertNotProtectedPreview(rootResponse, page, '/');
    expect(rootResponse?.status(), 'Production root should load without protection or routing errors.').toBeLessThan(400);

    await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeEnabled();
    const emailDisclosure = page.getByRole('button', { name: 'Sign in with email' });
    await expect(emailDisclosure).toBeVisible();
    await emailDisclosure.click();
    await expect(page.getByLabel('Email')).toBeVisible();
    await expect(page.locator('input[type="password"]')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();

    const signInResponse = await page.goto(routeURL('/auth/sign-in'));
    await assertNotProtectedPreview(signInResponse, page, '/auth/sign-in');
    expect(signInResponse?.status(), 'Production sign-in route should load without protection or routing errors.').toBeLessThan(400);
    await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeEnabled();
    await expect(page.getByLabel('Email')).toBeVisible();
    await expect(page.locator('input[type="password"]')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sign in', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Create account', exact: true })).toBeVisible();
    await expect(page.getByRole('link', { name: 'Forgot password?' })).toBeVisible();
  });

  test('deployed app exposes the expected immutable frontend build revision', async ({ page }) => {
    test.skip(
      !hostedMode && !expectedFrontendSha,
      'Local smoke runs enforce frontend identity only when BRASSTUNE_EXPECTED_FRONTEND_SHA is set.',
    );
    const expectedRevision = expectedFrontendSha ?? '';
    expect(
      expectedRevision,
      'Hosted smoke requires BRASSTUNE_EXPECTED_FRONTEND_SHA as a full 40-character Git commit SHA.',
    ).toMatch(/^[0-9a-f]{40}$/);

    const rootResponse = await page.goto(routeURL('/'));
    await assertNotProtectedPreview(rootResponse, page, '/');
    expect(rootResponse?.status(), 'Revision identity requires a loadable deployed root.').toBeLessThan(400);
    await expect(
      page.locator('meta[name="brasstune-build-revision"]'),
      'The deployed page must expose its immutable build revision.',
    ).toHaveAttribute('content', expectedRevision);
  });

  test('deployed app loads root and deep links without mixed content', async ({ page }) => {
    await grantGuestAccess(page);
    const consoleErrors: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', (error) => consoleErrors.push(error.message));

    for (const route of routes) {
      const response = await page.goto(routeURL(route));
      await assertNotProtectedPreview(response, page, route);
      expect(response?.status(), `${route} should not be behind auth or missing`).toBeLessThan(400);
      await expect(page.locator('main .screen-container')).toBeVisible();
      await expect(page.locator('.route-loading')).toHaveCount(0);
      await expect(page.locator('.route-error')).toHaveCount(0);
      if (!route.startsWith('/auth/') && route !== '/') {
        const expectedPath = expectedRoutePaths.get(route) ?? route;
        await expect.poll(
          () => new URL(page.url()).pathname,
          { message: `${route} should resolve to ${expectedPath} instead of the auth gateway` },
        ).toBe(expectedPath);
      }
      await expect(page.locator('body')).not.toContainText(/mixed content/i);
      await expect(page.locator('body')).not.toContainText(/vercel authentication|log in to vercel|single sign-on|authentication required/i);
      await page.evaluate(async () => {
        await document.fonts.ready;
      });
    }

    expect(consoleErrors.filter((message) => !harmlessBrowserErrors.has(message))).toEqual([]);
  });

  test('hosted runtime URLs do not fall back to localhost or Vercel same-origin API paths', async ({ page }) => {
    test.skip(!hostedMode, 'Hosted URL hygiene is covered only for deployed smoke runs.');
    await grantGuestAccess(page);
    const appOrigin = new URL(process.env.E2E_BASE_URL ?? page.url()).origin;
    const badURLs: string[] = [];
    page.on('request', (request) => {
      const url = request.url();
      if (!url.startsWith('http')) return;
      try {
        assertNoHostedURLRegression(url, appOrigin);
      } catch {
        badURLs.push(url);
      }
    });
    page.on('websocket', (socket) => {
      try {
        assertNoHostedURLRegression(socket.url(), appOrigin);
      } catch {
        badURLs.push(socket.url());
      }
    });
    const response = await page.goto(routeURL('/practice'));
    await assertNotProtectedPreview(response, page, '/practice');
    await expect(page.getByText(/Live mic/i)).toBeVisible();
    await expect(page.getByLabel('Instrument').locator('option').first()).toBeAttached();
    expect(badURLs).toEqual([]);
  });

  test('configured backend health responds for hosted smoke', async ({ request }) => {
    expect(apiBaseURL, 'Set E2E_API_BASE_URL to include backend readiness in hosted smoke tests.').toBeTruthy();
    const response = await request.get(`${apiBaseURL}/api/ready`, {
      headers: { Origin: process.env.E2E_BASE_URL ?? '' },
    });
    expect(response.ok()).toBe(true);
    expect(response.headers()['access-control-allow-origin'] ?? '').toBe(process.env.E2E_BASE_URL);
  });

  test('configured backend CORS preflights app origins for read and write routes', async ({ request }) => {
    expect(apiBaseURL, 'Set E2E_API_BASE_URL to include backend CORS in hosted smoke tests.').toBeTruthy();
    for (const [path, method] of [['/api/ready', 'GET'], ['/api/sessions/start', 'POST']] as const) {
      const response = await request.fetch(`${apiBaseURL}${path}`, {
        method: 'OPTIONS',
        headers: {
          Origin: process.env.E2E_BASE_URL ?? '',
          'Access-Control-Request-Method': method,
          'Access-Control-Request-Headers': 'content-type,authorization',
        },
      });
      expect(response.ok(), `${path} preflight should pass`).toBe(true);
      expect(response.headers()['access-control-allow-origin'] ?? '').toBe(process.env.E2E_BASE_URL);
    }
  });

  test('configured WebSocket URL uses secure transport for https app', async ({ page }) => {
    expect(wsBaseURL, 'Set E2E_WS_BASE_URL to include WebSocket URL checks.').toBeTruthy();
    await grantGuestAccess(page);
    const response = await page.goto(routeURL('/settings/audio-lab'));
    await assertNotProtectedPreview(response, page, '/settings/audio-lab');
    const appUrl = new URL(process.env.E2E_BASE_URL ?? page.url());
    if (appUrl.protocol === 'https:') {
      expect(wsBaseURL?.startsWith('wss://')).toBe(true);
    }
  });

  test('configured WebSocket upgrades and returns an app-level auth response', async ({ page }) => {
    expect(wsBaseURL, 'Set E2E_WS_BASE_URL to include WebSocket handshake checks.').toBeTruthy();
    await grantGuestAccess(page);
    await page.goto(routeURL('/settings/audio-lab'));
    const outcome = await page.evaluate(async (baseURL) => {
      const url = new URL('/ws/pitch', baseURL).toString();
      return await new Promise<{ type: string; data?: string; code?: number; reason?: string; opened?: boolean }>((resolve) => {
        const ws = new WebSocket(url);
        let opened = false;
        const timer = window.setTimeout(() => {
          ws.close(1000, 'smoke timeout');
          resolve({ type: 'timeout', opened });
        }, 10000);
        ws.onopen = () => {
          opened = true;
          ws.send(JSON.stringify({ type: 'ping' }));
        };
        ws.onmessage = (event) => {
          window.clearTimeout(timer);
          const data = String(event.data);
          ws.close(1000, 'smoke complete');
          resolve({ type: 'message', data, opened });
        };
        ws.onerror = () => {
          if (!opened) {
            window.clearTimeout(timer);
            resolve({ type: 'error', opened });
          }
        };
        ws.onclose = (event) => {
          window.clearTimeout(timer);
          resolve({ type: 'close', code: event.code, reason: event.reason, opened });
        };
      });
    }, wsBaseURL);
    expect(outcome.type, JSON.stringify(outcome)).toBe('message');
    const payload = JSON.parse(outcome.data ?? '{}');
    expect([payload.type, payload.message]).toContain('Authenticate before sending pitch frames.');
  });

  test('strict hosted branch content is current when enabled', async ({ page }) => {
    test.skip(!strictHostedContent, 'Strict content validation runs only after deploying this branch.');
    await grantGuestAccess(page);
    await page.goto(routeURL('/settings'));
    await expect(page.locator('body')).not.toContainText(/\/dev\/calibration|MVP|Developer testing|FastAPI|Supabase env vars/i);
    await page.goto(routeURL('/privacy'));
    await expect(page.getByText(/Privacy Policy/i)).toBeVisible();
  });
});
