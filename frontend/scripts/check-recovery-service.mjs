import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

// Publishing the landing-only site must not strand installed apps' reset links.
// This deployment preflight sends no recovery credentials or user data.
const origin = 'https://brasstune-u8qj.onrender.com';
const get = (path) => fetch(new URL(path, origin), {
  redirect: 'error',
  signal: AbortSignal.timeout(60000),
});
const page = await get('/auth/reset-password');
assert.equal(page.status, 200, 'Deploy the separate recovery service before publishing the marketing site.');
assert.ok(/^text\/html(?:;|$)/i.test(page.headers.get('content-type') || ''), 'Recovery page must be served as HTML.');
assert.match(page.headers.get('cache-control') || '', /no-store/);
assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
assert.match(page.headers.get('x-robots-tag') || '', /noindex/);
assert.equal(page.headers.get('cross-origin-opener-policy'), 'same-origin');
const csp = page.headers.get('content-security-policy') || '';
const expectedCSP = ["default-src 'none'", "script-src 'self'", "style-src 'self'", 'connect-src https://yznziwewxrlwnwiynlvl.supabase.co', "form-action 'none'", "base-uri 'none'", "frame-ancestors 'none'"];
const directives = csp.split(';').map((part) => part.trim()).filter(Boolean);
assert.ok(directives.length === expectedCSP.length && expectedCSP.every((part) => directives.includes(part)), 'Recovery must enforce the reviewed restrictive CSP.');
assert.ok(page.headers.get('x-content-type-options') === 'nosniff', 'Recovery must disable MIME sniffing.');
assert.ok(page.headers.get('x-frame-options') === 'DENY', 'Recovery must deny framing.');
assert.ok(page.headers.get('cross-origin-resource-policy') === 'same-origin', 'Recovery resources must stay same-origin.');
const permissions = page.headers.get('permissions-policy') || '';
for (const feature of ['camera', 'microphone', 'geolocation', 'payment']) {
  assert.ok(permissions.split(',').map((part) => part.trim()).includes(`${feature}=()`), 'Recovery must disable unneeded permissions.');
}
const html = await page.text();
assert.ok(/id="recovery-form"/.test(html), 'Recovery form must be present.');
assert.ok(/src="\/auth\/recovery\/recovery.js"/.test(html), 'Recovery script must be present.');
const configMatch = html.match(/<script id="recovery-public-config" type="application\/json">(.*?)<\/script>/s);
assert.ok(configMatch, 'Recovery public configuration must be present.');
const config = JSON.parse(configMatch[1]);
assert.ok(config.supabaseUrl === 'https://yznziwewxrlwnwiynlvl.supabase.co', 'Recovery must use the expected project.');
assert.ok(/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(config.publishableKey || ''), 'Recovery must expose only a valid public key.');
const script = await get('/auth/recovery/recovery.js');
assert.equal(script.status, 200);
assert.ok(/^(?:text|application)\/javascript(?:;|$)/i.test(script.headers.get('content-type') || ''), 'Recovery script must have a JavaScript MIME type.');
assert.ok(script.headers.get('x-content-type-options') === 'nosniff', 'Recovery script must disable MIME sniffing.');
assert.ok(script.headers.get('cross-origin-resource-policy') === 'same-origin', 'Recovery script must stay same-origin.');
assert.match(script.headers.get('cache-control') || '', /no-store/);
// Vercel may upload only frontend/, so carry the reviewed server-script digest.
const contract = JSON.parse(await readFile(new URL('../marketing/recovery-contract.json', import.meta.url), 'utf8'));
assert.ok(contract.schemaVersion === 1 && /^[a-f0-9]{64}$/.test(contract.scriptSHA256 || ''), 'Recovery release contract must be valid.');
assert.ok(createHash('sha256').update(await script.text(), 'utf8').digest('hex') === contract.scriptSHA256, 'Deploy the reviewed recovery script before publishing its bridge.');
console.log('Deployed recovery service configuration, headers and script match the marketing migration.');
