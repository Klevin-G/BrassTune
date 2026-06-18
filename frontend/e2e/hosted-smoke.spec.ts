import { expect, test } from 'playwright/test';

const apiBaseURL = process.env.E2E_API_BASE_URL;
const wsBaseURL = process.env.E2E_WS_BASE_URL;
const strictHostedContent = process.env.E2E_STRICT_HOSTED_CONTENT === '1';

test.describe('hosted read-only smoke', () => {
  test('deployed app loads root and deep links without mixed content', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', (error) => consoleErrors.push(error.message));

    const routes = [
      ['/', /Today's intonation focus/i],
      ['/practice', /Live tuner cockpit/i],
      ['/settings/audio-lab', /Audio Calibration Lab|Calibration/i],
    ] as const;
    const strictRoutes = strictHostedContent ? [...routes, ['/privacy', /Privacy Policy/i] as const] : routes;

    for (const [route, text] of strictRoutes) {
      await page.goto(route);
      await expect(page.getByRole('main').getByText(text).first()).toBeVisible();
      await expect(page.locator('body')).not.toContainText(/mixed content/i);
    }

    expect(consoleErrors.filter((message) => !/favicon|ResizeObserver/i.test(message))).toEqual([]);
  });

  test('configured backend health responds for hosted smoke', async ({ request }) => {
    test.skip(!apiBaseURL, 'Set E2E_API_BASE_URL to include backend health in hosted smoke tests.');
    const response = await request.get(`${apiBaseURL}/api/health`, {
      headers: { Origin: process.env.E2E_BASE_URL ?? '' },
    });
    expect(response.ok()).toBe(true);
    expect(response.headers()['access-control-allow-origin'] ?? '').not.toBe('*');
  });

  test('configured WebSocket URL uses secure transport for https app', async ({ page }) => {
    test.skip(!wsBaseURL, 'Set E2E_WS_BASE_URL to include WebSocket URL checks.');
    await page.goto('/settings/audio-lab');
    const appUrl = new URL(process.env.E2E_BASE_URL ?? page.url());
    if (appUrl.protocol === 'https:') {
      expect(wsBaseURL?.startsWith('wss://')).toBe(true);
    }
  });
});
