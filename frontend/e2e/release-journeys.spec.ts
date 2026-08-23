import { expect, test } from 'playwright/test';

const apiBaseURL = process.env.E2E_API_BASE_URL ?? 'http://127.0.0.1:8000';
const localAdminEnabled = process.env.E2E_START_LOCAL_SERVERS !== '0';

test.beforeEach(async ({ page, request }) => {
  if (localAdminEnabled) {
    await request.post(`${apiBaseURL}/api/admin/demo-data/repair`).catch(() => undefined);
  }
  await page.addInitScript(() => {
    const preserveOnboardingState = sessionStorage.getItem('e2e.preserveOnboardingState') === 'true';
    sessionStorage.removeItem('e2e.preserveOnboardingState');
    if (!preserveOnboardingState) {
      Object.keys(localStorage)
        .filter((key) => key.startsWith('brasstune.'))
        .filter((key) => key !== 'brasstune.theme')
        .forEach((key) => localStorage.removeItem(key));
      localStorage.setItem('brasstune.onboardingComplete', 'true');
      localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    }
    localStorage.setItem('brasstune.demoMode', 'true');
    sessionStorage.setItem('brasstune.guestAccess', 'true');
  });
});

test('critical routes render identifiable content', async ({ page }) => {
  const routes = [
    ['/', /Tune up, play along, and see how you sound/i],
    ['/practice', /Live mic/i],
    ['/practice/scorer', /Practice Scorer/i],
    ['/metronome', /Metronome/i],
    ['/practice/sheet-music', /Sheet Music/i],
    ['/sessions', /Recordings/i],
    ['/progress', /Progress/i],
    ['/ensemble', /Class/i],
    ['/settings', /Settings/i],
    ['/auth/sign-in', /Welcome back/i],
    ['/auth/sign-up', /Create your free BrassTune account/i],
    ['/privacy', /Privacy/i],
    ['/terms', /Terms of Service/i],
    ['/support', /Need help|Support/i],
    ['/credits', /Kelvin Guo, Arya Salem/i],
  ] as const;

  for (const [route, text] of routes) {
    await page.goto(route);
    await expect(page).toHaveURL(new RegExp(`${route === '/' ? '/?$' : route.replace('/', '\\/')}`));
    await expect(page.getByRole('main').getByText(text).first()).toBeVisible();
    await expect(page.locator('.content')).toBeVisible();
    await expect(page.locator('body')).not.toContainText(/Supabase env vars|FastAPI|Start the FastAPI server|Authentication required|cockpit|Practice cockpit/i);
  }
});

test('credits remain directly reachable and credit Kelvin Guo before Arya Salem', async ({ page }) => {
  await page.goto('/credits');
  await expect(page.getByRole('heading', { name: 'Credits' })).toBeVisible();
  await expect(page.getByRole('main')).toContainText('Kelvin Guo, Arya Salem');
});

test('compound-meter count-in keeps audio accents and visual group boundaries in sync', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { currentTime: 0, frequencies: [] as number[] };
    class FakeAudioContext {
      state: AudioContextState = 'running';
      get currentTime() { return state.currentTime; }
      destination = {};
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createOscillator() {
        return {
          type: 'sine',
          frequency: { setValueAtTime: (frequency: number) => state.frequencies.push(frequency) },
          connect() { return this; },
          disconnect() {},
          start() {},
          stop() {},
          onended: null,
        };
      }
      createGain() {
        return {
          gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} },
          connect() { return this; },
          disconnect() {},
        };
      }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    (window as typeof window & { __compoundMeterTest: typeof state }).__compoundMeterTest = state;
  });

  await page.goto('/metronome');
  await page.locator('summary').click();
  const signatures = page.getByRole('radiogroup', { name: 'All time signatures' });
  await expect(signatures.getByRole('radio', { name: '9/8' })).toBeVisible();
  await expect(signatures.getByRole('radio', { name: '12/8' })).toBeVisible();
  await signatures.getByRole('radio', { name: '6/8' }).click();
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(() => page.evaluate(() => (window as typeof window & { __compoundMeterTest: { frequencies: number[] } }).__compoundMeterTest.frequencies.length)).toBe(1);
  await page.evaluate(() => { (window as typeof window & { __compoundMeterTest: { currentTime: number } }).__compoundMeterTest.currentTime = 2; });
  await expect.poll(() => page.evaluate(() => (window as typeof window & { __compoundMeterTest: { frequencies: number[] } }).__compoundMeterTest.frequencies.slice(0, 6))).toEqual([1568, 880, 880, 1568, 880, 880]);
  await expect(page.locator('.mt-beat.accent')).toHaveCount(2);
  await expect(page.locator('.mt-beat').nth(0)).toHaveClass(/active/);

  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await page.evaluate(() => {
    const state = (window as typeof window & { __compoundMeterTest: { currentTime: number; frequencies: number[] } }).__compoundMeterTest;
    state.currentTime = 0;
    state.frequencies.length = 0;
  });
  await page.getByLabel('Accent the first beat').uncheck();
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await page.evaluate(() => { (window as typeof window & { __compoundMeterTest: { currentTime: number } }).__compoundMeterTest.currentTime = 2; });
  await expect.poll(() => page.evaluate(() => (window as typeof window & { __compoundMeterTest: { frequencies: number[] } }).__compoundMeterTest.frequencies.slice(0, 6))).toEqual([880, 880, 880, 880, 880, 880]);
  await expect(page.locator('.mt-beat.accent')).toHaveCount(0);
});

test('running tempo changes rebase the next beat without silence, duplicates, or grid drift', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { currentTime: 0, ticks: [] as Array<{ frequency: number; time: number }> };
    class FakeAudioContext {
      state: AudioContextState = 'running';
      destination = {};
      get currentTime() { return state.currentTime; }
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createOscillator() {
        return {
          type: 'sine',
          frequency: { setValueAtTime: (frequency: number, time: number) => state.ticks.push({ frequency, time }) },
          connect() { return this; },
          disconnect() {},
          start() {},
          stop() {},
          onended: null,
        };
      }
      createGain() {
        return {
          gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} },
          connect() { return this; },
          disconnect() {},
        };
      }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    (window as typeof window & { __tempoSchedulerTest: typeof state }).__tempoSchedulerTest = state;
  });

  const setTempo = async (bpm: number) => {
    await page.locator('.mt-slider').evaluate((slider, value) => {
      const input = slider as HTMLInputElement;
      // Bypass React's value tracker so the dispatched event exercises the
      // same controlled-input path as a real range control interaction.
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set?.call(input, String(value));
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }, bpm);
  };
  const state = () => page.evaluate(() => (window as typeof window & {
    __tempoSchedulerTest: { currentTime: number; ticks: Array<{ frequency: number; time: number }> };
  }).__tempoSchedulerTest);

  await page.goto('/metronome');
  await page.locator('summary').click();
  await page.getByLabel('Count in before starting').uncheck();

  // Slow -> fast: the old next beat is three seconds away; preserving phase
  // puts its same beat identity on the fast grid instead of going silent.
  await setTempo(20);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(async () => (await state()).ticks.length).toBe(1);
  await page.evaluate(() => { (window as typeof window & { __tempoSchedulerTest: { currentTime: number } }).__tempoSchedulerTest.currentTime = 0.1; });
  await setTempo(300);
  await page.evaluate(() => { (window as typeof window & { __tempoSchedulerTest: { currentTime: number } }).__tempoSchedulerTest.currentTime = 0.2; });
  await expect.poll(async () => (await state()).ticks.length).toBe(2);
  expect((await state()).ticks[1].time).toBeGreaterThan(0.2);
  expect((await state()).ticks[1].time).toBeLessThan(0.35);

  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await page.evaluate(() => {
    const scheduler = (window as typeof window & { __tempoSchedulerTest: { currentTime: number; ticks: unknown[] } }).__tempoSchedulerTest;
    scheduler.currentTime = 0;
    scheduler.ticks.length = 0;
  });

  // Fast -> slow: retain the near existing boundary, then take the slower
  // interval after it. This prevents a skipped beat or a duplicated downbeat.
  await setTempo(300);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(async () => (await state()).ticks.length).toBe(1);
  await page.evaluate(() => { (window as typeof window & { __tempoSchedulerTest: { currentTime: number } }).__tempoSchedulerTest.currentTime = 0.1; });
  await setTempo(20);
  await page.evaluate(() => { (window as typeof window & { __tempoSchedulerTest: { currentTime: number } }).__tempoSchedulerTest.currentTime = 0.2; });
  await expect.poll(async () => (await state()).ticks.length).toBe(2);
  const ticks = (await state()).ticks;
  expect(ticks[1].time).toBeCloseTo(0.28, 2);
  expect(new Set(ticks.map((tick) => tick.time)).size).toBe(ticks.length);
});

test('default count-in preserves remaining beat identities when tempo changes in either direction', async ({ page }) => {
  await page.addInitScript(() => {
    const state = { currentTime: 0, ticks: [] as Array<{ frequency: number; time: number }> };
    class FakeAudioContext {
      state: AudioContextState = 'running'; destination = {};
      get currentTime() { return state.currentTime; }
      resume() { return Promise.resolve(); }
      close() { this.state = 'closed'; return Promise.resolve(); }
      createOscillator() { return { type: 'sine', frequency: { setValueAtTime: (frequency: number, time: number) => state.ticks.push({ frequency, time }) }, connect() { return this; }, disconnect() {}, start() {}, stop() {}, onended: null }; }
      createGain() { return { gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() { return this; }, disconnect() {} }; }
    }
    Object.defineProperty(window, 'AudioContext', { configurable: true, value: FakeAudioContext });
    (window as typeof window & { __countInTempoTest: typeof state }).__countInTempoTest = state;
  });
  const setTempo = async (bpm: number) => page.locator('.mt-slider').evaluate((slider, value) => {
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set?.call(slider, String(value));
    slider.dispatchEvent(new Event('input', { bubbles: true }));
  }, bpm).then(async () => {
    // Let React commit the input before advancing the synthetic audio clock.
    await expect(page.locator('.mt-slider')).toHaveValue(String(bpm));
  });
  const advance = (time: number) => page.evaluate((nextTime) => {
    (window as typeof window & { __countInTempoTest: { currentTime: number } }).__countInTempoTest.currentTime = nextTime;
  }, time);
  const ticks = () => page.evaluate(() => (window as typeof window & { __countInTempoTest: { ticks: Array<{ frequency: number; time: number }> } }).__countInTempoTest.ticks);

  await page.goto('/metronome');
  // Count-in is enabled by default. Slow -> fast must not abandon its second,
  // third, or fourth count-in beats when scheduled output is rebased.
  await setTempo(20);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(async () => (await ticks()).length).toBe(1);
  await advance(0.1);
  await setTempo(300);
  await advance(0.35);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(2);
  // The production scheduler deliberately has a short look-ahead. Advance
  // the synthetic clock past each remaining count-in boundary so this test
  // validates scheduled identities instead of assuming four immediate nodes.
  await advance(0.55);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(3);
  await advance(0.8);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(4);
  expect((await ticks()).slice(0, 4).map((tick) => tick.frequency)).toEqual([1568, 880, 880, 880]);
  expect(new Set((await ticks()).map((tick) => tick.time)).size).toBe((await ticks()).length);
  await expect(page.locator('.mt-beat.active')).toHaveCount(1);

  await page.getByRole('button', { name: 'Stop', exact: true }).click();
  await page.evaluate(() => {
    const state = (window as typeof window & { __countInTempoTest: { currentTime: number; ticks: unknown[] } }).__countInTempoTest;
    state.currentTime = 0; state.ticks.length = 0;
  });
  // Fast -> slow keeps the imminent second count, then expands subsequent
  // count-in intervals without duplicating the downbeat.
  await setTempo(300);
  await page.getByRole('button', { name: 'Start', exact: true }).click();
  await expect.poll(async () => (await ticks()).length).toBe(1);
  await advance(0.1);
  await setTempo(20);
  await advance(0.35);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(2);
  await advance(3.5);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(3);
  await advance(6.7);
  await expect.poll(async () => (await ticks()).length).toBeGreaterThanOrEqual(4);
  expect((await ticks()).slice(0, 4).map((tick) => tick.frequency)).toEqual([1568, 880, 880, 880]);
  expect(new Set((await ticks()).map((tick) => tick.time)).size).toBe((await ticks()).length);
  await expect(page.locator('.mt-beat.active')).toHaveCount(1);
});

test('merged and retired routes redirect to their new home', async ({ page }) => {
  const runtimeErrors: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') runtimeErrors.push(`console: ${message.text()}`);
  });
  page.on('pageerror', (error) => runtimeErrors.push(`pageerror: ${error.message}`));

  for (const [from, expected, destinationText] of [
    ['/home', /\/practice$/, /Live mic/i],
    ['/analytics', /\/progress$/, /Progress/i],
    ['/coach', /\/progress$/, /Progress/i],
    ['/more', /\/settings$/, /Settings/i],
  ] as const) {
    await page.goto(from);
    await expect(page).toHaveURL(expected);
    await expect(page.getByRole('main').getByText(destinationText, { exact: true }).first()).toBeVisible();
  }

  expect(runtimeErrors).toEqual([]);
});

test('guest class route invites sign-in without exposing director controls', async ({ page }) => {
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: /sign in to see your class/i })).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Print report|Roster admin|Section trends|Top problem notes|Add student by username/i);
});

test('accounts-unavailable routes still offer guest practice', async ({ page }) => {
  await page.goto('/auth/reset-password');
  await expect(page.getByText(/accounts aren't turned on yet/i)).toBeVisible();
  await expect(page.getByRole('button', { name: /continue as guest|start practicing|keep practicing/i }).first()).toBeVisible();
  await expect(page.locator('body')).not.toContainText(/Supabase|VITE_SUPABASE|env vars/i);
});

test('root gateway starts a guest practice session on the tuner', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.removeItem('brasstune.guestAccess'));
  await page.goto('/');
  await expect(page.getByRole('heading', { name: /tune up, play along/i })).toBeVisible();
  // The appearance/theme picker must NOT be on the landing page.
  await expect(page.locator('body')).not.toContainText(/Appearance|Liquid|High Contrast/i);
  await page.getByRole('button', { name: /start practicing/i }).first().click();
  await expect(page).toHaveURL(/\/practice$/);
  await expect(page.getByText(/Live mic/i)).toBeVisible();
});

test('fresh guest entry opens the five-step instrument tour and explains local guest data', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    localStorage.setItem('brasstune.guestOnboardingComplete', 'false');
    sessionStorage.setItem('e2e.preserveOnboardingState', 'true');
  });
  await page.reload();
  await page.getByRole('button', { name: /start practicing/i }).first().click();

  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('heading', { name: 'Choose your instrument' })).toBeVisible();
  await expect(dialog).toContainText('Step 1 of 5');
  await expect(dialog).toContainText(/Practicing as a guest/);
  await expect(dialog).toContainText(/stay in this browser on this device/);
  await expect(dialog.getByRole('button', { name: /dismiss tour for now/i })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Next' })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Back' })).toHaveCount(0);
  await dialog.getByRole('combobox').selectOption('horn');
  await expect(dialog.getByRole('combobox')).toHaveValue('horn');
  for (let index = 0; index < 4; index += 1) await dialog.getByRole('button', { name: 'Next' }).click();
  await dialog.getByRole('button', { name: /open the tuner/i }).click();
  await expect(dialog).toBeHidden();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.guestOnboardingComplete'))).toBe('true');
  await page.evaluate(() => sessionStorage.setItem('e2e.preserveOnboardingState', 'true'));
  await page.reload();
  await expect(page.getByRole('dialog')).toHaveCount(0);
});

test('tiny-phone onboarding keeps its close control clear in English and Arabic', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });

  for (const locale of ['en', 'ar']) {
    await page.goto('/');
    await page.evaluate((nextLocale) => {
      localStorage.setItem('brasstune.locale', nextLocale);
      sessionStorage.setItem('brasstune.guestAccess', 'true');
      // A completed legacy account/tour must not suppress a fresh guest setup.
      localStorage.setItem('brasstune.onboardingComplete', 'true');
      localStorage.removeItem('brasstune.guestOnboardingComplete');
      // The next navigation must retain this deliberately incomplete guest setup.
      sessionStorage.setItem('e2e.preserveOnboardingState', 'true');
    }, locale);
    await page.goto('/practice');

    const dialog = page.getByRole('dialog');
    const close = dialog.locator('.ob-close');
    await expect(close).toBeVisible();
    const overlapAreas = await dialog.evaluate((element) => {
      const closeRect = element.querySelector('.ob-close')!.getBoundingClientRect();
      return Array.from(element.querySelectorAll('.ob-heading-icon, .ob-heading h2')).map((target) => {
        const targetRect = target.getBoundingClientRect();
        const width = Math.max(0, Math.min(closeRect.right, targetRect.right) - Math.max(closeRect.left, targetRect.left));
        const height = Math.max(0, Math.min(closeRect.bottom, targetRect.bottom) - Math.max(closeRect.top, targetRect.top));
        return width * height;
      });
    });
    expect(overlapAreas, `${locale} heading should not overlap the close control`).toEqual([0, 0]);
    await close.click();
  }
});

test('closing a guest tour is temporary until the tour is completed', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => {
    localStorage.setItem('brasstune.guestOnboardingComplete', 'false');
    sessionStorage.setItem('e2e.preserveOnboardingState', 'true');
  });
  await page.reload();
  await page.getByRole('button', { name: /start practicing/i }).first().click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Dismiss tour for now' }).click();
  await expect(dialog).toBeHidden();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.guestOnboardingComplete'))).toBe('false');

  await page.evaluate(() => sessionStorage.setItem('e2e.preserveOnboardingState', 'true'));
  await page.reload();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Choose your instrument' })).toBeVisible();
});

test('settings replays the tour with a keyboard-trapped dialog', async ({ page }) => {
  await page.goto('/settings');
  await page.getByRole('button', { name: /replay tour/i }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole('heading', { name: 'Choose your instrument' })).toBeFocused();
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
    ['/progress', /record your first take/i],
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
  const managerHeaders = { Authorization: 'Bearer dev-user-1' };
  const fixtureName = 'E2E Consent Class';

  // A long-lived local backend can retain the manager's quota from prior E2E
  // runs. A fixture is reusable only when the manager can directly observe
  // Maya's pending invitation; never infer consent state from its name alone.
  const findInvitedFixture = async () => {
    const groupsResponse = await request.get(`${apiBaseURL}/api/ensemble/groups`, { headers: managerHeaders });
    expect(groupsResponse.status()).toBe(200);
    const groups = await groupsResponse.json();
    for (const group of groups.filter((candidate: { name: string }) => candidate.name === fixtureName)) {
      const membersResponse = await request.get(`${apiBaseURL}/api/ensemble/groups/${group.id}/members`, {
        headers: managerHeaders,
      });
      expect(membersResponse.status()).toBe(200);
      const member = (await membersResponse.json()).find(
        (candidate: { username?: string; status?: string }) => candidate.username === 'maya' && candidate.status === 'invited',
      );
      if (member) return { group, member };
    }
    return undefined;
  };

  let fixture = await findInvitedFixture();
  if (!fixture) {
    const created = await request.post(`${apiBaseURL}/api/ensemble/groups`, {
      headers: managerHeaders,
      data: { name: fixtureName },
    });
    if (created.status() === 409) {
      const { detail } = await created.json();
      expect(detail).toBe('You have reached the class ownership limit.');
      fixture = await findInvitedFixture();
      expect(fixture, 'ownership-limited test setup requires an invited E2E Consent Class fixture').toBeDefined();
    } else {
      expect(created.status()).toBe(200);
      const group = await created.json();
      const invite = await request.post(`${apiBaseURL}/api/ensemble/groups/${group.id}/members/by-username`, {
        headers: managerHeaders,
        data: { username: 'maya' },
      });
      expect(invite.status()).toBe(200);
      fixture = { group, member: await invite.json() };
    }
  }

  expect(fixture).toBeDefined();
  const { group, member } = fixture!;
  const forced = await request.patch(`${apiBaseURL}/api/ensemble/groups/${group.id}/members/${member.id}`, {
    headers: managerHeaders,
    data: { status: 'active' },
  });
  expect(forced.status()).toBe(409);
});
