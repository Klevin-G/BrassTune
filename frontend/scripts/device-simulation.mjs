import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const frontendDir = path.resolve(__dirname, '..');
const rootDir = path.resolve(frontendDir, '..');
const backendDir = path.join(rootDir, 'backend');
const screenshotDir = path.join(rootDir, 'docs', 'assets', 'device-simulation');
const reportPath = path.join(rootDir, 'docs', 'device-simulation-report.md');
const appUrl = 'http://127.0.0.1:5173';
const apiUrl = 'http://127.0.0.1:8000/api/instruments';
const isWindows = process.platform === 'win32';

const viewports = [
  { name: 'Tiny phone', slug: 'tiny-phone', width: 320, height: 568, kind: 'phone' },
  { name: 'Phone small', slug: 'phone-small', width: 360, height: 740, kind: 'phone' },
  { name: 'iPhone modern', slug: 'iphone-modern', width: 393, height: 852, kind: 'phone' },
  { name: 'Large phone', slug: 'large-phone', width: 430, height: 932, kind: 'phone' },
  { name: 'Foldable narrow tablet', slug: 'foldable-narrow-tablet', width: 540, height: 720, kind: 'phone' },
  { name: 'iPad portrait', slug: 'ipad-portrait', width: 768, height: 1024, kind: 'tablet-portrait' },
  { name: 'iPad landscape', slug: 'ipad-landscape', width: 1024, height: 768, kind: 'tablet-landscape' },
  { name: 'iPad Pro landscape', slug: 'ipad-pro-landscape', width: 1366, height: 1024, kind: 'desktop' },
  { name: 'Laptop', slug: 'laptop', width: 1440, height: 900, kind: 'desktop' },
  { name: 'Wide desktop analytics', slug: 'wide-desktop', width: 1728, height: 1117, kind: 'wide-desktop' },
  { name: 'Desktop HD', slug: 'desktop-hd', width: 1920, height: 1080, kind: 'wide-desktop' },
  { name: 'Ultra-wide desktop', slug: 'ultra-wide-desktop', width: 2560, height: 1440, kind: 'wide-desktop' },
];

const routesVisited = ['Home', 'Auth', 'Onboarding', 'Practice', 'Session Review', 'Analytics', 'Coach', 'Sessions', 'Progress', 'Ensemble', 'More', 'Settings', 'Audio Lab'];

const screenshotPlan = new Map([
  ['tiny-phone:practice', 'tiny-phone-practice.png'],
  ['iphone-modern:home', 'phone-home.png'],
  ['iphone-modern:auth', 'phone-auth.png'],
  ['iphone-modern:onboarding', 'phone-onboarding.png'],
  ['iphone-modern:practice', 'phone-practice.png'],
  ['iphone-modern:analytics', 'phone-analytics.png'],
  ['iphone-modern:session-review', 'phone-session-review.png'],
  ['iphone-modern:sessions', 'phone-session-playback.png'],
  ['ipad-portrait:practice', 'ipad-portrait-practice.png'],
  ['ipad-landscape:practice', 'ipad-landscape-practice.png'],
  ['ipad-landscape:analytics', 'ipad-landscape-analytics.png'],
  ['laptop:home', 'desktop-home.png'],
  ['laptop:practice', 'desktop-practice.png'],
  ['wide-desktop:analytics', 'desktop-analytics-dashboard.png'],
  ['ultra-wide-desktop:analytics', 'ultrawide-analytics-dashboard.png'],
  ['laptop:session-review', 'desktop-session-review.png'],
  ['laptop:ensemble', 'desktop-ensemble.png'],
  ['laptop:audio-lab', 'audio-lab.png'],
]);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function isReachable(url) {
  try {
    const response = await fetch(url);
    return response.ok;
  } catch {
    return false;
  }
}

async function waitFor(url, label, timeoutMs = 20000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await isReachable(url)) return;
    await sleep(250);
  }
  throw new Error(`${label} did not become reachable at ${url}`);
}

function spawnServer(command, args, cwd, env = {}) {
  const child = spawn(command, args, { cwd, env: { ...process.env, ...env }, stdio: 'pipe', shell: false, windowsHide: true });
  child.stdout.on('data', () => {});
  child.stderr.on('data', () => {});
  return child;
}

async function exists(filePath) {
  return fs.access(filePath).then(() => true).catch(() => false);
}

async function backendServerCommand() {
  const venvPython = isWindows
    ? path.join(backendDir, '.venv', 'Scripts', 'python.exe')
    : path.join(backendDir, '.venv', 'bin', 'python');
  if (await exists(venvPython)) {
    return { command: venvPython, args: ['-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000'] };
  }
  if (isWindows) {
    return { command: 'py', args: ['-3', '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000'] };
  }
  return { command: 'python3', args: ['-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000'] };
}

async function ensureServers() {
  const started = [];
  if (!(await isReachable(apiUrl))) {
    const backend = await backendServerCommand();
    started.push(spawnServer(backend.command, backend.args, backendDir));
  }
  if (!(await isReachable(appUrl))) {
    started.push(spawnServer(isWindows ? 'npm.cmd' : 'npm', ['run', 'dev', '--', '--host', '127.0.0.1', '--port', '5173'], frontendDir, {
      VITE_API_BASE_URL: 'http://127.0.0.1:8000',
      VITE_WS_BASE_URL: 'ws://127.0.0.1:8000',
      VITE_SUPABASE_URL: '',
      VITE_SUPABASE_PUBLISHABLE_KEY: '',
    }));
  }
  await waitFor(apiUrl, 'FastAPI');
  await waitFor(appUrl, 'Vite');
  return started;
}

function stopServers(children) {
  for (const child of children) {
    if (!child.killed) child.kill('SIGINT');
  }
}

async function assertNoConsoleErrors(page, issues, label) {
  const pageErrors = await page.evaluate(() => window.__brasstuneErrors ?? []);
  for (const error of pageErrors) issues.push(`${label}: ${error}`);
}

async function assertNoHorizontalOverflow(page, issues, label) {
  const overflow = await page.evaluate(() => {
    const viewportWidth = document.documentElement.clientWidth;
    const documentOverflow = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth) - viewportWidth;
    const offenders = [...document.body.querySelectorAll('*')]
      .filter((element) => {
        if (element.closest('.table-wrap')) return false;
        const rect = element.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return false;
        return rect.right > viewportWidth + 2 || rect.left < -2 || element.scrollWidth - element.clientWidth > 2;
      })
      .slice(0, 8)
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return `${element.tagName.toLowerCase()}.${[...element.classList].join('.')} ${Math.round(rect.left)}-${Math.round(rect.right)}`;
      });
    return { documentOverflow, offenders };
  });
  if (overflow.documentOverflow > 2 && overflow.offenders.length > 0) {
    issues.push(`${label}: horizontal overflow ${Math.round(overflow.documentOverflow)}px from ${overflow.offenders.join(', ')}`);
  }
}

async function assertMobileChrome(page, viewport, issues, label) {
  if (viewport.width > 860) return;
  const state = await page.evaluate(() => {
    const sidebar = document.querySelector('.sidebar');
    const tabbar = document.querySelector('.floating-tabbar');
    const navRect = tabbar?.getBoundingClientRect();
    const navVisible = !!tabbar && getComputedStyle(tabbar).display !== 'none' && !!navRect && navRect.height > 0;
    const sidebarHidden = !sidebar || getComputedStyle(sidebar).display === 'none';
    const overlappedButtons = [];
    if (navVisible && navRect) {
      const buttons = [...document.querySelectorAll('.primary-button, .session-controls button')].filter((button) => !button.closest('.floating-tabbar'));
      for (const button of buttons) {
        const rect = button.getBoundingClientRect();
        const visible = rect.bottom > 0 && rect.top < window.innerHeight;
        const overlaps = visible && rect.left < navRect.right && rect.right > navRect.left && rect.top < navRect.bottom && rect.bottom > navRect.top;
        if (overlaps) overlappedButtons.push(button.textContent?.trim() || button.className);
      }
    }
    return { navVisible, sidebarHidden, overlappedButtons };
  });
  if (!state.sidebarHidden) issues.push(`${label}: sidebar should be hidden on mobile`);
  if (!state.navVisible) issues.push(`${label}: floating tab bar should be visible on mobile`);
  if (state.overlappedButtons.length > 0) issues.push(`${label}: bottom nav overlaps buttons ${state.overlappedButtons.join(', ')}`);
}

async function assertTunerDominant(page, viewport, issues, label) {
  const state = await page.evaluate(() => {
    const note = document.querySelector('.note-display strong');
    if (!note) return { visible: false, width: 0, height: 0 };
    const rect = note.getBoundingClientRect();
    return { visible: rect.width > 0 && rect.height > 0, width: rect.width, height: rect.height };
  });
  const minWidth = viewport.width <= 430 ? 120 : viewport.width <= 1180 ? 170 : 220;
  const minHeight = viewport.width <= 430 ? 72 : viewport.width <= 1180 ? 92 : 118;
  if (!state.visible || (state.width < minWidth && state.height < minHeight)) {
    issues.push(`${label}: tuner note is not visually dominant (${Math.round(state.width)}px wide, ${Math.round(state.height)}px tall)`);
  }
}

async function assertSideBySide(page, selector, issues, label) {
  const state = await page.evaluate((selectorText) => {
    const container = document.querySelector(selectorText);
    if (!container || container.children.length < 2) return { ok: false, reason: 'missing children' };
    const first = container.children[0].getBoundingClientRect();
    const second = container.children[1].getBoundingClientRect();
    return {
      ok: Math.abs(first.top - second.top) < 24 && first.width > 260 && second.width > 240,
      firstWidth: first.width,
      secondWidth: second.width,
      topDelta: Math.abs(first.top - second.top),
    };
  }, selector);
  if (!state.ok) {
    issues.push(`${label}: expected side-by-side ${selector}, got widths ${Math.round(state.firstWidth ?? 0)}/${Math.round(state.secondWidth ?? 0)} and top delta ${Math.round(state.topDelta ?? 0)}`);
  }
}

async function saveScreenshot(page, viewport, key, screenshots) {
  const fileName = screenshotPlan.get(`${viewport.slug}:${key}`);
  if (!fileName) return;
  await page.screenshot({ path: path.join(screenshotDir, fileName), fullPage: key !== 'sessions' });
  screenshots.push(fileName);
}

async function gotoAndCheck(page, viewport, route, routeLabel, issues) {
  await page.goto(`${appUrl}${route}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('.content', { state: 'visible' });
  await assertNoConsoleErrors(page, issues, `${viewport.name} ${routeLabel}`);
  await assertNoHorizontalOverflow(page, issues, `${viewport.name} ${routeLabel}`);
  if (routeLabel !== 'Auth') {
    await assertMobileChrome(page, viewport, issues, `${viewport.name} ${routeLabel}`);
  }
}

async function runViewport(browser, viewport) {
  const context = await browser.newContext({ viewport: { width: viewport.width, height: viewport.height }, deviceScaleFactor: 1 });
  await context.addInitScript(() => {
    localStorage.clear();
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    window.__brasstuneErrors = [];
    window.addEventListener('unhandledrejection', (event) => {
      window.__brasstuneErrors.push(`Unhandled rejection: ${event.reason?.message || event.reason}`);
    });
    window.addEventListener('error', (event) => {
      window.__brasstuneErrors.push(`Window error: ${event.message}`);
    });
  });
  const page = await context.newPage();
  const issues = [];
  const screenshots = [];
  page.on('console', (message) => {
    if (message.type() === 'error') issues.push(`${viewport.name} console: ${message.text()}`);
  });
  page.on('pageerror', (error) => issues.push(`${viewport.name} pageerror: ${error.message}`));

  try {
    await gotoAndCheck(page, viewport, '/', 'Home', issues);
    await saveScreenshot(page, viewport, 'home', screenshots);

    await gotoAndCheck(page, viewport, '/auth/sign-in', 'Auth', issues);
    await saveScreenshot(page, viewport, 'auth', screenshots);
    if (viewport.slug === 'iphone-modern') {
      await gotoAndCheck(page, viewport, '/settings', 'Settings onboarding trigger', issues);
      await page.getByRole('button', { name: /reopen onboarding/i }).click();
      await page.waitForSelector('.onboarding-panel', { state: 'visible' });
      await assertNoHorizontalOverflow(page, issues, `${viewport.name} Onboarding`);
      await saveScreenshot(page, viewport, 'onboarding', screenshots);
      await page.getByRole('button', { name: /skip/i }).click();
    }

    await gotoAndCheck(page, viewport, '/practice', 'Practice', issues);
    await assertTunerDominant(page, viewport, issues, `${viewport.name} Practice`);
    if (viewport.kind === 'tablet-landscape') await assertSideBySide(page, '.practice-layout', issues, `${viewport.name} Practice`);
    await saveScreenshot(page, viewport, 'practice', screenshots);

    await page.getByRole('button', { name: /start recording/i }).click();
    await page.getByRole('button', { name: /stop recording/i }).waitFor({ state: 'visible' });
    await sleep(2600);
    await page.getByRole('button', { name: /stop recording/i }).click();
    const reviewLink = page.getByRole('link', { name: /review session/i });
    await reviewLink.waitFor({ state: 'visible', timeout: 15000 });
    const reviewHref = await reviewLink.getAttribute('href');
    if (!reviewHref) issues.push(`${viewport.name} Practice: saved session review link missing href`);
    await reviewLink.click();
    await page.waitForURL(/\/sessions\/-?\d+/);
    await page.waitForLoadState('networkidle');
    await page.waitForSelector('.two-column-grid', { state: 'visible', timeout: 15000 });
    await page.waitForSelector('.audio-player-card', { state: 'visible', timeout: 15000 }).catch(() => {
      issues.push(`${viewport.name} Session Review: playback UI did not appear after demo recording`);
    });
    await assertNoHorizontalOverflow(page, issues, `${viewport.name} Session Review`);
    if (viewport.kind === 'tablet-landscape') await assertSideBySide(page, '.two-column-grid', issues, `${viewport.name} Session Review`);
    await saveScreenshot(page, viewport, 'session-review', screenshots);

    await gotoAndCheck(page, viewport, '/analytics', 'Analytics', issues);
    if (viewport.width >= 900) await assertSideBySide(page, '.analytics-main-grid', issues, `${viewport.name} Analytics`);
    if (viewport.width >= 1200) await assertSideBySide(page, '.analytics-chart-grid', issues, `${viewport.name} Analytics charts`);
    const heatCell = page.locator('.heat-cell').filter({ hasNotText: 'no data' }).first();
    await heatCell.click();
    await page.getByRole('radio', { name: '7D' }).click();
    await page.waitForLoadState('networkidle');
    await assertNoConsoleErrors(page, issues, `${viewport.name} Analytics interactions`);
    await saveScreenshot(page, viewport, 'analytics', screenshots);

    await gotoAndCheck(page, viewport, '/coach', 'Coach', issues);
    await gotoAndCheck(page, viewport, '/sessions', 'Sessions', issues);
    await saveScreenshot(page, viewport, 'sessions', screenshots);
    await gotoAndCheck(page, viewport, '/progress', 'Progress', issues);
    await gotoAndCheck(page, viewport, '/ensemble', 'Ensemble', issues);
    await saveScreenshot(page, viewport, 'ensemble', screenshots);
    await gotoAndCheck(page, viewport, '/more', 'More', issues);
    await gotoAndCheck(page, viewport, '/settings', 'Settings', issues);
    await gotoAndCheck(page, viewport, '/settings/audio-lab', 'Audio Lab', issues);
    await saveScreenshot(page, viewport, 'audio-lab', screenshots);
  } catch (error) {
    issues.push(`Fatal simulation error: ${error.message}`);
  } finally {
    await context.close().catch(() => {});
  }
  return { viewport, issues, screenshots, routes: routesVisited };
}

async function writeReport(results) {
  const lines = [
    '# Device Simulation Report',
    '',
    `Generated: ${new Date().toISOString()}`,
    '',
    'The committed Playwright harness was used for repeatable multi-viewport browser automation.',
    '',
    '## Summary',
    '',
    '| Viewport | Size | Routes Visited | Result | Issues |',
    '| --- | ---: | --- | --- | --- |',
  ];
  for (const result of results) {
    lines.push(`| ${result.viewport.name} | ${result.viewport.width}x${result.viewport.height} | ${result.routes.join(', ')} | ${result.issues.length ? 'Fail' : 'Pass'} | ${result.issues.length ? result.issues.join('<br>') : 'None'} |`);
  }
  lines.push('', '## Screenshots Generated', '');
  const screenshots = results.flatMap((result) => result.screenshots.map((file) => ({ file, viewport: result.viewport.name })));
  for (const shot of screenshots) {
    lines.push(`- ${shot.file} (${shot.viewport})`);
  }
  lines.push('', '## Remaining Risks', '');
  lines.push('- Playwright Chromium covers layout and interaction behavior, but not Safari/WebKit rendering differences on physical iPad hardware.');
  lines.push('- Demo recording creates local sample sessions during simulation; this is expected for the current local MVP database.');
  lines.push('- CI cannot exercise native iOS camera pickers or choose a physical local video from Photos; those checks remain in the manual phone test plan.');
  lines.push('- Tables are intentionally allowed to scroll horizontally only inside `.table-wrap` when the advanced mobile table is opened.');
  await fs.writeFile(reportPath, `${lines.join('\n')}\n`);
}

async function main() {
  await fs.mkdir(screenshotDir, { recursive: true });
  await fs.rm(screenshotDir, { recursive: true, force: true });
  await fs.mkdir(screenshotDir, { recursive: true });
  const servers = await ensureServers();
  const browser = await chromium.launch({ headless: true });
  const results = [];
  try {
    for (const viewport of viewports) {
      results.push(await runViewport(browser, viewport));
    }
  } finally {
    await browser.close();
    stopServers(servers);
  }
  await writeReport(results);
  const failures = results.filter((result) => result.issues.length > 0);
  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`${failure.viewport.name}:`);
      for (const issue of failure.issues) console.error(`  - ${issue}`);
    }
    process.exit(1);
  }
  console.log(`Device simulation passed. Report: ${reportPath}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
