import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    sessionStorage.setItem('brasstune.guestAccess', 'true');
    // Init scripts run again after reload. Seed a fresh guest once rather than
    // overwriting the durable completion that this journey is asserting.
    if (localStorage.getItem('brasstune.guestOnboardingComplete') === null) {
      localStorage.setItem('brasstune.guestOnboardingComplete', 'false');
    }
  });
});

test('five-step tour supports navigation, escape, replay, and tuner completion', async ({ page }) => {
  await page.goto('/practice');
  await expect(page.getByText('App tour · Step 1 of 5')).toBeVisible();
  await page.getByRole('button', { name: 'Next' }).click();
  await expect(page.getByText('App tour · Step 2 of 5')).toBeVisible();
  await page.getByRole('button', { name: 'Back' }).click();
  await expect(page.getByText('App tour · Step 1 of 5')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await page.evaluate(() => localStorage.setItem('brasstune.guestOnboardingComplete', 'true'));
  await page.reload();
  await page.goto('/settings');
  await page.getByRole('button', { name: 'Replay tour' }).click();
  for (let index = 0; index < 4; index += 1) await page.getByRole('button', { name: 'Next' }).click();
  await expect(page.getByText('App tour · Step 5 of 5')).toBeVisible();
  await page.getByRole('button', { name: 'Open the tuner' }).click();
  await expect(page).toHaveURL(/\/practice$/);
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.guestOnboardingComplete'))).toBe('true');
});

test('tiny RTL tour remains within the viewport', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.addInitScript(() => localStorage.setItem('brasstune.locale', 'ar'));
  await page.goto('/practice');
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect.poll(() => page.locator('.ob-panel').evaluate((panel) => panel.scrollWidth <= window.innerWidth)).toBeTruthy();
});
