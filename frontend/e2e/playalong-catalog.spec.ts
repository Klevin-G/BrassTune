import { expect, test } from 'playwright/test';

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    Object.keys(localStorage)
      .filter((key) => key.startsWith('brasstune.'))
      .filter((key) => key !== 'brasstune.theme')
      .forEach((key) => localStorage.removeItem(key));
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
});

test('groups every major and natural minor scale in accessible controls', async ({ page }) => {
  await page.goto('/practice/scorer');

  const majorGroup = page.getByRole('heading', { name: 'Major scales', exact: true }).locator('..');
  const minorGroup = page.getByRole('heading', { name: 'Minor scales', exact: true }).locator('..');
  const otherGroup = page.getByRole('heading', { name: 'Other exercises', exact: true }).locator('..');

  await expect(majorGroup.getByRole('button')).toHaveCount(12);
  await expect(minorGroup.getByRole('button')).toHaveCount(12);
  await expect(otherGroup.getByRole('button')).toHaveCount(3);

  const dFlatMajor = majorGroup.getByRole('button', { name: 'D♭ major', exact: true });
  await dFlatMajor.focus();
  await expect(dFlatMajor).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(dFlatMajor).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('Play the D♭ major scale going up.', { exact: true })).toBeVisible();

  const cSharpMinor = minorGroup.getByRole('button', { name: 'C♯ minor', exact: true });
  await cSharpMinor.focus();
  await page.keyboard.press('Space');
  await expect(cSharpMinor).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('Play the C♯ minor scale going up as a natural minor scale.', { exact: true })).toBeVisible();
});

test('legacy scorer links canonicalize without losing their exercise query or hash', async ({ page }) => {
  await page.goto('/practice/play-along?exercise=cmaj#target-note');
  await expect(page).toHaveURL(/\/practice\/scorer\?exercise=cmaj#target-note$/);
  await expect(page.getByRole('link', { name: 'Practice Scorer' })).toHaveClass(/active/);
});

for (const width of [320, 375]) {
  test(`catalog has no horizontal page overflow at ${width} CSS pixels`, async ({ page }) => {
    await page.setViewportSize({ width, height: 720 });
    await page.goto('/practice/scorer');
    await expect(page.getByRole('heading', { name: 'Major scales', exact: true })).toBeVisible();

    const dimensions = await page.evaluate(() => ({
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));
    expect(dimensions.scrollWidth).toBeLessThanOrEqual(dimensions.clientWidth);
  });
}
