import { spawn, spawnSync } from 'node:child_process';
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
  { name: 'Wide desktop', slug: 'wide-desktop', width: 1728, height: 1117, kind: 'wide-desktop' },
  { name: 'Desktop HD', slug: 'desktop-hd', width: 1920, height: 1080, kind: 'wide-desktop' },
  { name: 'Ultra-wide desktop', slug: 'ultra-wide-desktop', width: 2560, height: 1440, kind: 'wide-desktop' },
];

export function selectViewports(configuredViewports, requestedSlugs = '') {
  const requested = requestedSlugs
    .split(',')
    .map((slug) => slug.trim())
    .filter(Boolean);
  if (requested.length === 0) return configuredViewports;
  const known = new Map(configuredViewports.map((viewport) => [viewport.slug, viewport]));
  const unknown = requested.filter((slug) => !known.has(slug));
  if (unknown.length > 0) {
    throw new Error(`Unknown device simulation viewport${unknown.length === 1 ? '' : 's'}: ${unknown.join(', ')}`);
  }
  return requested.map((slug) => known.get(slug));
}

const screenshotPlan = new Map([
  ['tiny-phone:practice', 'tiny-phone-practice.png'],
  ['iphone-modern:auth', 'phone-auth.png'],
  ['iphone-modern:onboarding', 'phone-onboarding.png'],
  ['iphone-modern:practice', 'phone-practice.png'],
  ['iphone-modern:progress', 'phone-progress.png'],
  ['iphone-modern:session-review', 'phone-session-review.png'],
  ['iphone-modern:sessions', 'phone-session-playback.png'],
  ['ipad-portrait:practice', 'ipad-portrait-practice.png'],
  ['ipad-landscape:practice', 'ipad-landscape-practice.png'],
  ['ipad-landscape:progress', 'ipad-landscape-progress.png'],
  ['laptop:practice', 'desktop-practice.png'],
  ['wide-desktop:progress', 'desktop-progress-dashboard.png'],
  ['ultra-wide-desktop:progress', 'ultrawide-progress-dashboard.png'],
  ['laptop:session-review', 'desktop-session-review.png'],
  ['laptop:ensemble', 'desktop-ensemble.png'],
  ['laptop:settings', 'desktop-settings.png'],
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

export function assertSimulationPortsAvailable({ apiReachable, appReachable }) {
  const occupied = [apiReachable ? apiUrl : null, appReachable ? appUrl : null].filter(Boolean);
  if (occupied.length > 0) {
    throw new Error(`Device simulation refuses to reuse unverified servers at ${occupied.join(', ')}. Stop them so this checkout can start and own both servers.`);
  }
}

export function formatCheckoutIdentity(sha, dirty) {
  return `${sha}${dirty ? ' (dirty worktree)' : ' (clean worktree)'}`;
}

function currentCheckoutIdentity() {
  const revision = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: rootDir, encoding: 'utf8', shell: false });
  const status = spawnSync('git', ['status', '--porcelain'], { cwd: rootDir, encoding: 'utf8', shell: false });
  if (revision.status !== 0 || status.status !== 0) {
    throw new Error('Device simulation could not verify the checkout Git identity.');
  }
  return { sha: revision.stdout.trim(), dirty: status.stdout.trim().length > 0 };
}

async function waitFor(url, label, timeoutMs = 20000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    if (await isReachable(url)) return;
    await sleep(250);
  }
  throw new Error(`${label} did not become reachable at ${url}`);
}

const childClosePromises = new WeakMap();

function spawnServer(command, args, cwd, env = {}) {
  const child = spawn(command, args, {
    cwd,
    env: { ...process.env, ...env },
    stdio: 'ignore',
    shell: false,
    windowsHide: true,
    detached: !isWindows,
  });
  childClosePromises.set(child, new Promise((resolve) => {
    child.once('close', resolve);
    child.once('error', () => {});
  }));
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
  try {
    const [apiReachable, appReachable] = await Promise.all([isReachable(apiUrl), isReachable(appUrl)]);
    assertSimulationPortsAvailable({ apiReachable, appReachable });
    const backend = await backendServerCommand();
    started.push(spawnServer(backend.command, backend.args, backendDir, {
      APP_ENV: 'local',
      FRONTEND_ORIGIN: appUrl,
      CORS_ALLOWED_ORIGINS: `${appUrl},http://localhost:5173,http://127.0.0.1:5173`,
    }));
    const viteBin = path.join(frontendDir, 'node_modules', 'vite', 'bin', 'vite.js');
    started.push(spawnServer(process.execPath, [viteBin, '--host', '127.0.0.1', '--port', '5173'], frontendDir, {
      VITE_API_BASE_URL: 'http://127.0.0.1:8000',
      VITE_WS_BASE_URL: 'ws://127.0.0.1:8000',
      VITE_SUPABASE_URL: '',
      VITE_SUPABASE_PUBLISHABLE_KEY: '',
      VITE_E2E_DISABLE_SUPABASE: 'true',
      VITE_ENABLE_INTERNAL_TOOLS: 'false',
    }));
    await waitFor(apiUrl, 'FastAPI');
    await waitFor(appUrl, 'Vite');
    return started;
  } catch (startupError) {
    try {
      await stopServers(started);
    } catch (cleanupError) {
      throw new AggregateError([startupError, cleanupError], 'Device simulation servers failed to start and clean up.');
    }
    throw startupError;
  }
}

function waitForChildClose(child, timeoutMs) {
  const closePromise = childClosePromises.get(child);
  if (!closePromise) return Promise.resolve(true);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (closed) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(closed);
    };
    const timer = setTimeout(() => finish(false), timeoutMs);
    closePromise.then(() => finish(true), () => finish(true));
  });
}

async function stopWindowsProcessTree(child) {
  if (!child.pid) return;
  const killer = spawn('taskkill.exe', ['/pid', String(child.pid), '/t', '/f'], { stdio: 'ignore', windowsHide: true });
  await new Promise((resolve) => {
    killer.once('close', resolve);
    killer.once('error', resolve);
  });
  if (!(await waitForChildClose(child, 3000))) {
    throw new Error(`Windows dev server process tree ${child.pid} did not stop cleanly.`);
  }
}

function signalPosixProcessGroup(pid, signal) {
  try {
    process.kill(-pid, signal);
  } catch (error) {
    if (error?.code !== 'ESRCH') throw error;
  }
}

function posixProcessGroupExists(pid) {
  try {
    process.kill(-pid, 0);
    return true;
  } catch (error) {
    if (error?.code === 'EPERM') return true;
    if (error?.code === 'ESRCH') return false;
    throw error;
  }
}

async function waitForPosixProcessGroupExit(pid, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (!posixProcessGroupExists(pid)) return true;
    await sleep(50);
  }
  return !posixProcessGroupExists(pid);
}

async function stopPosixProcessTree(child) {
  if (!child.pid) return;
  signalPosixProcessGroup(child.pid, 'SIGTERM');
  if (!(await waitForPosixProcessGroupExit(child.pid, 3000))) {
    signalPosixProcessGroup(child.pid, 'SIGKILL');
    if (!(await waitForPosixProcessGroupExit(child.pid, 1000))) {
      throw new Error(`POSIX dev server process group ${child.pid} survived cleanup.`);
    }
  }
  if (!(await waitForChildClose(child, 1000))) {
    throw new Error(`Dev server process ${child.pid} closed its group but not its process handle.`);
  }
}

async function stopServers(children) {
  const results = await Promise.allSettled(children.map((child) => (
    isWindows ? stopWindowsProcessTree(child) : stopPosixProcessTree(child)
  )));
  const failures = results.filter((result) => result.status === 'rejected').map((result) => result.reason);
  if (failures.length > 0) {
    throw new AggregateError(failures, 'One or more dev server process trees did not stop cleanly.');
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
        if (overlaps) {
          const name = button.textContent?.trim() || button.className;
          overlappedButtons.push(`${name} (${Math.round(rect.top)}-${Math.round(rect.bottom)}px; nav ${Math.round(navRect.top)}-${Math.round(navRect.bottom)}px)`);
        }
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
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
  });
  await page.screenshot({ path: path.join(screenshotDir, fileName), fullPage: key !== 'sessions' });
  screenshots.push(fileName);
}

async function gotoAndCheck(page, viewport, route, routeLabel, issues) {
  await page.goto(`${appUrl}${route}`, { waitUntil: 'networkidle' });
  await page.waitForSelector('.content', { state: 'visible' });
  await assertNoConsoleErrors(page, issues, `${viewport.name} ${routeLabel}`);
  await assertNoHorizontalOverflow(page, issues, `${viewport.name} ${routeLabel}`);
  if (!routeLabel.startsWith('Auth')) {
    await assertMobileChrome(page, viewport, issues, `${viewport.name} ${routeLabel}`);
  }
}

export async function trackVerifiedRoute(routes, label, issues, verify) {
  const issueCount = issues.length;
  await verify();
  if (issues.length === issueCount && !routes.includes(label)) routes.push(label);
}

export async function trackConditionalRoute(condition, routes, label, issues, verify) {
  if (!condition) return false;
  await trackVerifiedRoute(routes, label, issues, verify);
  return true;
}

export async function dismissOnboardingDialog(dialog, timeoutMs = 3000) {
  const dismiss = dialog.getByRole('button', { name: /close for now|dismiss tour for now/i });
  if (await dismiss.count() === 0) {
    const available = await dialog.getByRole('button').allTextContents();
    throw new Error(`Onboarding opened without a supported dismiss action. Available buttons: ${available.filter(Boolean).join(', ') || 'none'}`);
  }
  await dismiss.first().click();
  await dialog.waitFor({ state: 'hidden', timeout: timeoutMs });
}

async function runViewport(browser, viewport) {
  console.log(`Simulating ${viewport.name} (${viewport.width}x${viewport.height})`);
  const context = await browser.newContext({ viewport: { width: viewport.width, height: viewport.height }, deviceScaleFactor: 1 });
  await context.addInitScript(() => {
    if (sessionStorage.getItem('brasstune.deviceSimulationInitialized') !== 'true') {
      localStorage.clear();
      sessionStorage.setItem('brasstune.deviceSimulationInitialized', 'true');
    }
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
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
  const routes = [];
  page.on('console', (message) => {
    if (message.type() === 'error') issues.push(`${viewport.name} console: ${message.text()}`);
  });
  page.on('pageerror', (error) => issues.push(`${viewport.name} pageerror: ${error.message}`));

  try {
    await trackVerifiedRoute(routes, 'Auth Gateway', issues, async () => {
      await gotoAndCheck(page, viewport, '/', 'Auth Gateway', issues);
      await saveScreenshot(page, viewport, 'auth', screenshots);
    });

    await trackVerifiedRoute(routes, 'Sign In', issues, () => gotoAndCheck(page, viewport, '/auth/sign-in', 'Auth Form', issues));
    await trackConditionalRoute(viewport.slug === 'iphone-modern', routes, 'Onboarding', issues, async () => {
      await gotoAndCheck(page, viewport, '/settings', 'Settings onboarding trigger', issues);
      await page.getByRole('button', { name: /replay tour/i }).click();
      const dialog = page.getByRole('dialog');
      await dialog.waitFor({ state: 'visible', timeout: 5000 });
      await assertNoHorizontalOverflow(page, issues, `${viewport.name} Onboarding`);
      await saveScreenshot(page, viewport, 'onboarding', screenshots);
      await dismissOnboardingDialog(dialog);
    });

    await trackVerifiedRoute(routes, 'Tuner', issues, async () => {
      await gotoAndCheck(page, viewport, '/practice', 'Practice', issues);
      await assertTunerDominant(page, viewport, issues, `${viewport.name} Practice`);
      await page.locator('.tuner-stage').waitFor({ state: 'visible' });
      await saveScreenshot(page, viewport, 'practice', screenshots);
    });

    await trackVerifiedRoute(routes, 'Play-Along', issues, () => gotoAndCheck(page, viewport, '/practice/play-along', 'Play-Along', issues));
    await trackVerifiedRoute(routes, 'Metronome', issues, () => gotoAndCheck(page, viewport, '/metronome', 'Metronome', issues));
    await trackVerifiedRoute(routes, 'Sheet Music', issues, () => gotoAndCheck(page, viewport, '/practice/score', 'Sheet Music', issues));
    const sessionReviewIssueCount = issues.length;
    await gotoAndCheck(page, viewport, '/practice', 'Practice return', issues);

    await page.getByRole('radio', { name: 'Demo', exact: true }).click();
    await page.getByRole('button', { name: /save this take/i }).click();
    await page.getByRole('button', { name: /stop and save/i }).waitFor({ state: 'visible' });
    await sleep(2600);
    await page.getByRole('button', { name: /stop and save/i }).click();
    const reviewLink = page.getByRole('link', { name: /see results/i });
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
    if (issues.length === sessionReviewIssueCount) routes.push('Session Review');

    await trackVerifiedRoute(routes, 'Progress', issues, async () => {
      await gotoAndCheck(page, viewport, '/progress', 'Progress', issues);
      await page.getByRole('heading', { name: /progress/i }).waitFor({ state: 'visible' });
      await saveScreenshot(page, viewport, 'progress', screenshots);
    });

    await trackVerifiedRoute(routes, 'Sessions', issues, async () => {
      await gotoAndCheck(page, viewport, '/sessions', 'Sessions', issues);
      await saveScreenshot(page, viewport, 'sessions', screenshots);
    });
    await trackVerifiedRoute(routes, 'Class', issues, async () => {
      await gotoAndCheck(page, viewport, '/ensemble', 'Class', issues);
      await saveScreenshot(page, viewport, 'ensemble', screenshots);
    });
    await trackVerifiedRoute(routes, 'Settings', issues, async () => {
      await gotoAndCheck(page, viewport, '/settings', 'Settings', issues);
      await saveScreenshot(page, viewport, 'settings', screenshots);
    });
  } catch (error) {
    issues.push(`Fatal simulation error: ${error.message}`);
  } finally {
    await context.close().catch(() => {});
  }
  return { viewport, issues, screenshots, routes };
}

async function writeReport(results, checkoutIdentity) {
  const lines = [
    '# Device Simulation Report',
    '',
    `Generated: ${new Date().toISOString()}`,
    `Checkout: ${formatCheckoutIdentity(checkoutIdentity.sha, checkoutIdentity.dirty)}`,
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
  const checkoutIdentity = currentCheckoutIdentity();
  console.log(`Device simulation checkout: ${formatCheckoutIdentity(checkoutIdentity.sha, checkoutIdentity.dirty)}`);
  await fs.mkdir(screenshotDir, { recursive: true });
  await fs.rm(screenshotDir, { recursive: true, force: true });
  await fs.mkdir(screenshotDir, { recursive: true });
  const servers = await ensureServers();
  let browser;
  let cleanupError = null;
  const results = [];
  const selectedViewports = selectViewports(viewports, process.env.DEVICE_SIMULATION_VIEWPORTS);
  try {
    browser = await chromium.launch({ headless: true });
    for (const viewport of selectedViewports) {
      results.push(await runViewport(browser, viewport));
    }
  } finally {
    try {
      await browser?.close();
    } catch (error) {
      cleanupError = error;
    }
    try {
      await stopServers(servers);
    } catch (error) {
      cleanupError ??= error;
    }
  }
  await writeReport(results, checkoutIdentity);
  if (cleanupError) throw cleanupError;
  const failures = results.filter((result) => result.issues.length > 0);
  if (failures.length > 0) {
    for (const failure of failures) {
      console.error(`${failure.viewport.name}:`);
      for (const issue of failure.issues) console.error(`  - ${issue}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log(`Device simulation passed. Report: ${reportPath}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
