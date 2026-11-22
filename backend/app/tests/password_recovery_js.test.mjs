import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import vm from 'node:vm';

const source = await readFile(resolve(import.meta.dirname, '..', 'static', 'recovery', 'recovery.js'), 'utf8');
const config = JSON.stringify({
  supabaseUrl: 'https://abcdefghijklmnopqrst.supabase.co',
  publishableKey: 'sb_publishable_0123456789abcdefghij',
});

function runRecovery(hash, fetchImpl = async () => ({ ok: true })) {
  const listeners = new Map();
  const elements = new Map([
    ['recovery-public-config', { textContent: config }],
    ['recovery-form', { hidden: true, addEventListener: (type, handler) => listeners.set(type, handler) }],
    ['password', { value: '' }],
    ['password-confirmation', { value: '' }],
    ['submit', { disabled: false }],
    ['status', { textContent: '' }],
  ]);
  const historyCalls = [];
  const forbiddenPersistence = new Proxy({}, { get() { throw new Error('persistent storage must not be read'); } });
  vm.runInNewContext(source, {
    URLSearchParams, Set, JSON, Date,
    document: { getElementById: (id) => elements.get(id) },
    location: { hash, pathname: '/auth/reset-password' },
    history: { replaceState: (_state, _title, path) => historyCalls.push(path) },
    fetch: fetchImpl,
    localStorage: forbiddenPersistence,
    sessionStorage: forbiddenPersistence,
    console: new Proxy({}, { get() { throw new Error('recovery page must not log'); } }),
  });
  return { elements, historyCalls, submit: listeners.get('submit') };
}

async function submitPassword(flow) {
  flow.elements.get('password').value = 'new-password';
  flow.elements.get('password-confirmation').value = 'new-password';
  await flow.submit({ preventDefault() {} });
}

async function settleInitialization() {
  await new Promise((resolveTick) => setImmediate(resolveTick));
}

const directRequests = [];
const success = runRecovery('#access_token=recovery-token&type=recovery&expires_at=4102444800', async (url, options) => {
  directRequests.push({ url, options });
  return { ok: true };
});
assert.deepEqual(success.historyCalls, ['/auth/reset-password']);
assert.equal(success.elements.get('recovery-form').hidden, false);
await submitPassword(success);
assert.equal(directRequests.length, 1);
assert.equal(directRequests[0].url, 'https://abcdefghijklmnopqrst.supabase.co/auth/v1/user');
assert.equal(directRequests[0].options.method, 'PUT');
assert.equal(directRequests[0].options.credentials, 'omit');
assert.equal(directRequests[0].options.referrerPolicy, 'no-referrer');
assert.equal(directRequests[0].options.headers.apikey, 'sb_publishable_0123456789abcdefghij');
assert.equal(directRequests[0].options.headers.Authorization, 'Bearer recovery-token');
assert.equal(success.elements.get('password').value, '');
assert.equal(success.elements.get('password-confirmation').value, '');
assert.match(success.elements.get('status').textContent, /password was updated/i);

for (const hash of ['', '#type=recovery', '#access_token=one&access_token=two&type=recovery', '#access_token=token&type=recovery&error=access_denied', '#access_token=token&type=recovery&expires_at=1']) {
  let calls = 0;
  const flow = runRecovery(hash, async () => { calls += 1; return { ok: true }; });
  assert.equal(flow.elements.get('recovery-form').hidden, true, hash);
  assert.equal(calls, 0, hash);
  assert.ok(flow.elements.get('status').textContent.length > 0, hash);
}

const verifier = 'v'.repeat(43);
const pkceRequests = [];
const pkce = runRecovery(`#code=recovery-code&type=recovery&code_verifier=${verifier}`, async (url, options) => {
  pkceRequests.push({ url, options });
  if (pkceRequests.length === 1) return { ok: true, json: async () => ({ access_token: 'exchanged-token' }) };
  return { ok: true };
});
assert.equal(pkceRequests.length, 1, 'PKCE exchange starts before the password form is shown');
assert.equal(pkce.elements.get('recovery-form').hidden, true);
await settleInitialization();
assert.equal(pkce.elements.get('recovery-form').hidden, false);
await submitPassword(pkce);
assert.equal(pkceRequests.length, 2);
assert.equal(pkceRequests[0].url, 'https://abcdefghijklmnopqrst.supabase.co/auth/v1/token?grant_type=pkce');
assert.equal(pkceRequests[0].options.headers.Authorization, 'Bearer sb_publishable_0123456789abcdefghij');
assert.deepEqual(JSON.parse(pkceRequests[0].options.body), { auth_code: 'recovery-code', code_verifier: verifier });
assert.equal(pkceRequests[1].url, 'https://abcdefghijklmnopqrst.supabase.co/auth/v1/user');
assert.equal(pkceRequests[1].options.headers.Authorization, 'Bearer exchanged-token');
assert.equal(pkce.elements.get('password').value, '');
assert.equal(pkce.elements.get('password-confirmation').value, '');
await submitPassword(pkce);
assert.equal(pkceRequests.length, 2, 'successful recovery clears the exchanged token before a second submit');

for (const hash of [`#code=recovery-code&type=recovery`, `#code=recovery-code&type=recovery&code_verifier=${verifier}&code_verifier=${verifier}`, '#code=recovery-code&access_token=token&type=recovery']) {
  const flow = runRecovery(hash);
  assert.equal(flow.elements.get('recovery-form').hidden, true, hash);
}
let exchangeThenUpdateCalls = 0;
const expiredPKCE = runRecovery(`#code=recovery-code&type=recovery&code_verifier=${verifier}`, async () => {
  exchangeThenUpdateCalls += 1;
  return { ok: false };
});
assert.equal(expiredPKCE.elements.get('recovery-form').hidden, true);
await settleInitialization();
assert.equal(exchangeThenUpdateCalls, 1);
assert.equal(expiredPKCE.elements.get('recovery-form').hidden, true);
assert.match(expiredPKCE.elements.get('status').textContent, /invalid or expired/i);

const rejected = runRecovery('#access_token=recovery-token&type=recovery', async () => ({ ok: false }));
await submitPassword(rejected);
assert.equal(rejected.elements.get('recovery-form').hidden, true);
assert.match(rejected.elements.get('status').textContent, /invalid or expired/i);
assert.ok(!source.includes('localStorage'));
assert.ok(!source.includes('sessionStorage'));
assert.ok(!source.includes('console.'));
console.log('password recovery browser-flow checks passed');
