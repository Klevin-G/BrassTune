import { expect, test } from 'playwright/test';
import type { Page, Response } from 'playwright/test';

const apiBaseURL = process.env.E2E_API_BASE_URL;
const wsBaseURL = process.env.E2E_WS_BASE_URL;
const strictHostedContent = process.env.E2E_STRICT_HOSTED_CONTENT === '1';
const hostedMode = process.env.E2E_START_LOCAL_SERVERS === '0';
const vercelShareURL = process.env.E2E_VERCEL_SHARE_URL;
const webBaseURL = process.env.E2E_BASE_URL;

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

async function skipProtectedPreview(response: Response | null, page: Page, route: string) {
  if (strictHostedContent || response?.status() !== 401) return;
  const baseHostname = webBaseURL ? new URL(webBaseURL).hostname : '';
  const unauthenticatedVercelPreview = baseHostname.endsWith('.vercel.app') && baseHostname !== 'brass-tune.vercel.app' && !vercelShareURL;
  if (unauthenticatedVercelPreview) {
    test.skip(true, `Protected Vercel preview returned 401 for ${route}; provide E2E_VERCEL_SHARE_URL or an automation bypass for page journeys.`);
  }
  const bodyText = await page.locator('body').innerText({ timeout: 5_000 }).catch(() => '');
  if (/vercel authentication|log in to vercel|single sign-on|authentication required/i.test(bodyText)) {
    test.skip(true, `Protected Vercel preview returned 401 for ${route}; provide E2E_VERCEL_SHARE_URL or an automation bypass for page journeys.`);
  }
}

test.describe('hosted read-only smoke', () => {
  test('deployed app loads root and deep links without mixed content', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', (error) => consoleErrors.push(error.message));

    for (const route of routes) {
      const response = await page.goto(routeURL(route));
      await skipProtectedPreview(response, page, route);
      expect(response?.status(), `${route} should not be behind auth or missing`).toBeLessThan(400);
      await expect(page.getByRole('main')).toBeVisible();
      await expect(page.locator('body')).not.toContainText(/mixed content/i);
      await expect(page.locator('body')).not.toContainText(/vercel authentication|log in to vercel|single sign-on|authentication required/i);
    }

    expect(consoleErrors.filter((message) => !/favicon|ResizeObserver/i.test(message))).toEqual([]);
  });

  test('hosted runtime URLs do not fall back to localhost or Vercel same-origin API paths', async ({ page }) => {
    test.skip(!hostedMode, 'Hosted URL hygiene is covered only for deployed smoke runs.');
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
    const response = await page.goto(routeURL('/settings/audio-lab'));
    await skipProtectedPreview(response, page, '/settings/audio-lab');
    await expect(page.getByText(/Cloud sync stream/i)).toBeVisible();
    await expect(page.getByText(/Connection diagnostics/i)).toBeVisible();
    expect(badURLs).toEqual([]);
  });

  test('configured backend health responds for hosted smoke', async ({ request }) => {
    test.skip(!apiBaseURL, 'Set E2E_API_BASE_URL to include backend health in hosted smoke tests.');
    const response = await request.get(`${apiBaseURL}/api/health`, {
      headers: { Origin: process.env.E2E_BASE_URL ?? '' },
    });
    expect(response.ok()).toBe(true);
    expect(response.headers()['access-control-allow-origin'] ?? '').toBe(process.env.E2E_BASE_URL);
  });

  test('configured backend CORS preflights app origins for read and write routes', async ({ request }) => {
    test.skip(!apiBaseURL, 'Set E2E_API_BASE_URL to include backend CORS in hosted smoke tests.');
    for (const [path, method] of [['/api/health', 'GET'], ['/api/sessions/start', 'POST']] as const) {
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
    test.skip(!wsBaseURL, 'Set E2E_WS_BASE_URL to include WebSocket URL checks.');
    const response = await page.goto(routeURL('/settings/audio-lab'));
    await skipProtectedPreview(response, page, '/settings/audio-lab');
    const appUrl = new URL(process.env.E2E_BASE_URL ?? page.url());
    if (appUrl.protocol === 'https:') {
      expect(wsBaseURL?.startsWith('wss://')).toBe(true);
    }
  });

  test('configured WebSocket upgrades and returns an app-level auth response', async ({ page }) => {
    test.skip(!wsBaseURL, 'Set E2E_WS_BASE_URL to include WebSocket handshake checks.');
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
    await page.goto(routeURL('/more'));
    await expect(page.locator('body')).not.toContainText(/\/dev\/calibration|MVP|Developer testing|FastAPI|Supabase env vars/i);
    await page.goto(routeURL('/privacy'));
    await expect(page.getByText(/Privacy Policy/i)).toBeVisible();
  });
});
