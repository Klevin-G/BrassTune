import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import vm from 'node:vm';

const dist = resolve(import.meta.dirname, '..', 'marketing-dist');
const paths = { '/':'index.html', '/privacy/':'privacy/index.html', '/terms/':'terms/index.html', '/support/':'support/index.html', '/credits/':'credits/index.html', '/assets/welcome-brass-instrument.jpg':'assets/welcome-brass-instrument.jpg' };
const server = createServer(async (request, response) => {
  const file = paths[request.url] ?? null;
  if (!file) return response.writeHead(404).end();
  try {
    if (file.endsWith('.jpg')) response.setHeader('content-type', 'image/jpeg');
    response.end(await readFile(resolve(dist, file)));
  } catch { response.writeHead(500).end(); }
});
await new Promise((resolveServer) => server.listen(0, '127.0.0.1', resolveServer));
const base = `http://127.0.0.1:${server.address().port}`;

async function assertWorkerRetirement() {
  const source = await readFile(resolve(dist, 'sw.js'), 'utf8');
  const listeners = new Map();
  const deleted = [];
  let unregistered = false;
  const self = {
    addEventListener(type, handler) { listeners.set(type, handler); },
    skipWaiting() {},
    registration: { unregister: async () => { unregistered = true; return true; } },
    get clients() { throw new Error('retirement worker must not access clients'); },
  };
  vm.runInNewContext(source, {
    self,
    caches: {
      keys: async () => ['workbox-precache-v1', 'brasstune-precache-v3', 'workbox-runtime-v1', 'user-media-cache'],
      delete: async (name) => { deleted.push(name); return true; },
    },
    Promise,
  });
  assert.ok(listeners.has('activate'));
  let activation;
  listeners.get('activate')({ waitUntil: (work) => { activation = work; } });
  await activation;
  assert.deepEqual(deleted, ['workbox-precache-v1', 'brasstune-precache-v3']);
  assert.equal(unregistered, true);
}

async function assertOAuthCleanup() {
  const source = await readFile(resolve(dist, 'site.js'), 'utf8');
  function run(pathname, search, hash) {
    let replacement = null;
    vm.runInNewContext(source, {
      navigator: { serviceWorker: { register: () => ({ catch() {} }) } },
      location: { pathname, search, hash },
      history: { replaceState: (_state, _title, value) => { replacement = value; } },
      URLSearchParams,
      Set,
    });
    return replacement;
  }
  assert.equal(run('/auth/callback', '?code=secret&state=state&keep=1', '#access_token=secret&refresh_token=secret&section=details'), '/auth/callback?keep=1#section=details');
  assert.equal(run('/privacy/', '?ref=band', '#details'), null);
  assert.equal(run('/auth/callback', '?error=denied&error_description=nope', '#provider_token=secret&provider_refresh_token=secret'), '/auth/callback');
}

async function assertBrassContrast() {
  const css = await readFile(resolve(dist, 'site.css'), 'utf8');
  const brass = css.match(/--brass:(#[0-9a-f]{6})/i)?.[1];
  assert.ok(brass, 'brass token must be a six-digit hex color');
  const luminance = (hex) => {
    const values = hex.slice(1).match(/../g).map((value) => Number.parseInt(value, 16) / 255).map((value) => value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
    return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2];
  };
  for (const background of ['#ffffff', '#f6f0e6']) {
    const ratio = (Math.max(luminance(brass), luminance(background)) + 0.05) / (Math.min(luminance(brass), luminance(background)) + 0.05);
    assert.ok(ratio >= 4.5, `brass token must meet 4.5:1 on ${background}; got ${ratio.toFixed(2)}:1`);
  }
}

try {
  for (const path of Object.keys(paths)) assert.equal((await fetch(base + path)).status, 200, `${path} must serve`);
  const image = await fetch(`${base}/assets/welcome-brass-instrument.jpg`);
  assert.equal(image.headers.get('content-type'), 'image/jpeg');
  assert.ok((await image.arrayBuffer()).byteLength > 0, 'welcome image must contain bytes');
  const home = await (await fetch(base + '/')).text();
  assert.match(home, /apps\.apple\.com\/us\/app\/id6795688588/);
  assert.match(home, /SoftwareApplication/);
  assert.match(home, /<img[^>]+welcome-brass-instrument\.jpg[^>]+alt="A brass trumpet/);
  for (const forbidden of ['/api/', 'sign in', 'sign up', 'continue as guest', '1.0.7', 'beta', 'android']) assert.ok(!home.toLowerCase().includes(forbidden), `home must not contain ${forbidden}`);
  for (const path of ['/', '/privacy/', '/terms/', '/support/', '/credits/']) {
    const html = await (await fetch(base + path)).text();
    assert.ok(!html.includes('/src/'), `${path} must not load app source`);
    assert.match(html, /src="\/site\.js"/);
    assert.match(html, /name="google-site-verification" content="MFaXR-0FemHDnUajM8HY2VtYEYjb9FVNGMNNjTxGrTQ"/);
    assert.match(html, new RegExp(`canonical" href="https://brasstune\\.vercel\\.app${path}`));
    const schema = JSON.parse(html.match(/<script type="application\/ld\+json">(.*?)<\/script>/s)[1]);
    assert.equal(schema.url, `https://brasstune.vercel.app${path}`);
    assert.equal(schema['@type'], path === '/' ? 'SoftwareApplication' : 'WebPage');
    if (path !== '/') {
      for (const field of ['operatingSystem', 'applicationCategory', 'offers', 'downloadUrl']) {
        assert.equal(schema[field], undefined, `legal page must not claim application property ${field}`);
      }
    }
  }
  const credits = await (await fetch(base + '/credits/')).text();
  for (const text of ['Kelvin Guo', 'Arya Salem', 'mark.drummer', 'CC BY 2.0', 'responsive crop']) assert.ok(credits.includes(text));
  await assertWorkerRetirement();
  await assertOAuthCleanup();
  await assertBrassContrast();
  const recoveryHTML = await readFile(resolve(dist, 'auth/reset-password/index.html'), 'utf8');
  assert.match(recoveryHTML, /noindex,nofollow/);
  assert.match(recoveryHTML, /src="\/recovery-bridge.js"/);
  assert.ok(!recoveryHTML.includes('/site.js'), 'Recovery bridge must not load the marketing OAuth cleanup');
  for (const configPath of ['../vercel.json', '../../vercel.json']) {
    const config = JSON.parse(await readFile(new URL(configPath, import.meta.url), 'utf8'));
    assert.ok(!config.redirects.some((rule) => rule.source === '/auth/:path*'), 'Recovery must not be caught by a generic auth redirect');
    assert.ok(config.headers.some((rule) => rule.source === '/recovery-bridge.js'
      && rule.headers.some((header) => header.key === 'Cache-Control' && header.value.includes('no-store'))));
  }
  await import('./test-recovery-bridge.mjs');
  const recoveryContract = JSON.parse(await readFile(new URL('../marketing/recovery-contract.json', import.meta.url), 'utf8'));
  const recoveryServerScript = await readFile(new URL('../../backend/app/static/recovery/recovery.js', import.meta.url));
  assert.equal(recoveryContract.scriptSHA256, createHash('sha256').update(recoveryServerScript).digest('hex'), 'Recovery publication pin must match the reviewed backend script');
  console.log('marketing static-site checks passed');
} finally {
  await new Promise((resolveServer) => server.close(resolveServer));
}
