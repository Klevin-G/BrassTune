import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fetchApprovedVercelURL } from '../../scripts/scoped-vercel-fetch.mjs';

const base = new URL(process.env.BRASSTUNE_WEB_BASE_URL || 'https://brasstune.vercel.app');
const bypassSecret = process.env.BRASSTUNE_VERCEL_AUTOMATION_BYPASS_SECRET || '';
const approved = (url) => url.protocol === 'https:' && (
  url.hostname === 'brasstune.vercel.app'
  || (url.hostname.startsWith('brass-tune-') && url.hostname.endsWith('-kelvis-prject.vercel.app'))
);
assert.ok(approved(base), 'Marketing smoke must target the approved BrassTune project.');

async function get(path) {
  const response = await fetchApprovedVercelURL(new URL(path, base).href, {
    bypassSecret,
    isApprovedURL: approved,
  });
  assert.equal(new URL(response.url).origin, base.origin, `${path} must stay on the target origin`);
  return response;
}

for (const path of ['/', '/privacy/', '/terms/', '/support/', '/credits/']) {
  const response = await get(path);
  assert.equal(response.status, 200, `${path} must return 200`);
  const html = await response.text();
  assert.match(html, /<html lang="en">/);
  assert.match(html, /name="google-site-verification"/);
  assert.ok(html.includes(`href="https://brasstune.vercel.app${path}"`), `${path} canonical`);
  assert.ok(!/<form\b|\/assets\/index-[^" ]+\.js|supabase-js/.test(html), `${path} must be informational`);
  const permissions = response.headers.get('permissions-policy') || '';
  assert.match(permissions, /microphone=\(\)/);
  assert.match(permissions, /camera=\(\)/);
  assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
  const csp = response.headers.get('content-security-policy') || '';
  const directives = csp.split(';').map((directive) => directive.trim());
  for (const required of ["default-src 'none'", "connect-src 'self'", "form-action 'none'"]) {
    assert.ok(directives.includes(required), `${path} must enforce ${required}`);
  }
  assert.ok(!/onrender\.com|supabase\.co/.test(csp), `${path} must not allow app service connections`);
  if (path === '/') {
    assert.match(html, /https:\/\/apps\.apple\.com\/us\/app\/id6795688588/);
    assert.match(html, /SoftwareApplication/);
  }
}
for (const path of ['/robots.txt', '/sitemap.xml', '/sw.js', '/site.js', '/site.css', '/recovery-bridge.js', '/assets/welcome-brass-instrument.jpg']) {
  const response = await get(path);
  assert.equal(response.status, 200, `${path} must return 200`);
  const body = Buffer.from(await response.arrayBuffer());
  assert.ok(body.byteLength > 0, `${path} must not be empty`);
  if (path === '/sw.js') {
    assert.match(response.headers.get('cache-control') || '', /no-store/);
    assert.equal(body.toString('utf8'), await readFile(new URL('../marketing/sw.js', import.meta.url), 'utf8'), 'The hosted worker must be the tested retirement worker');
  }
  if (path === '/recovery-bridge.js') {
    assert.match(response.headers.get('cache-control') || '', /no-store/);
    assert.equal(body.toString('utf8'), await readFile(new URL('../marketing/recovery-bridge.js', import.meta.url), 'utf8'));
  }
}
const recovery = await get('/auth/reset-password/');
assert.equal(recovery.status, 200);
assert.equal(new URL(recovery.url).pathname, '/auth/reset-password/');
assert.match(recovery.headers.get('cache-control') || '', /no-store/);
assert.match(recovery.headers.get('x-robots-tag') || '', /noindex/);
assert.match(await recovery.text(), /src="\/recovery-bridge.js"/);
for (const path of ['/practice', '/metronome', '/sessions', '/settings', '/auth/sign-in']) {
  const response = await get(path);
  assert.equal(response.status, 200);
  assert.equal(new URL(response.url).pathname, '/', `${path} must retire to the landing page`);
}
for (const path of ['/api/ready', '/ws/pitch']) {
  const response = await get(path);
  assert.equal(response.status, 404, `${path} must not expose app functionality on the website`);
}
console.log('Hosted marketing pages, assets, headers, App Store link and retired app routes passed.');
