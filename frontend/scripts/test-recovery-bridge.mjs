import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../marketing/recovery-bridge.js', import.meta.url), 'utf8');
const key = 'sb-yznziwewxrlwnwiynlvl-auth-token-code-verifier';
const verifier = 'a'.repeat(64);
function run({ search = '', hash = '', stored = null, storageError = false, removeError = false } = {}) {
  const events = [];
  const status = { textContent: '' };
  let destination;
  vm.runInNewContext(source, {
    document: { getElementById: (id) => { assert.equal(id, 'recovery-status'); return status; } },
    location: { search, hash, pathname: '/auth/reset-password/', replace: (url) => { events.push('navigate'); destination = new URL(url); } },
    history: { replaceState: (_state, _title, path) => { assert.equal(path, '/auth/reset-password/'); events.push('scrub'); } },
    localStorage: {
      getItem: (name) => { assert.equal(name, key); events.push('read-verifier'); if (storageError) throw new Error('blocked'); return stored; },
      removeItem: (name) => { assert.equal(name, key); events.push('remove-verifier'); if (removeError) throw new Error('blocked'); },
    },
    URLSearchParams, Set, Date,
  });
  assert.equal(events[0], 'scrub');
  if (destination) {
    assert.equal(destination.origin, 'https://brasstune-u8qj.onrender.com');
    assert.equal(destination.pathname, '/auth/reset-password');
    assert.equal(destination.search, '');
    assert.equal(events.at(-1), 'navigate');
  } else {
    assert.match(status.textContent, /Request a new password reset/);
  }
  return { destination, events };
}

const native = run({ hash: '#type=recovery&access_token=sample-token&refresh_token=DO-NOT-TRANSFER&token_type=bearer&expires_in=3600' });
assert.equal(native.destination.hash, '#type=recovery&access_token=sample-token');
assert.deepEqual(native.events, ['scrub', 'navigate']);
const legacy = run({ search: '?code=sample-code&next=https://untrusted.example/', stored: JSON.stringify(`${verifier}/recovery`) });
assert.equal(legacy.destination.hash, `#type=recovery&code=sample-code&code_verifier=${verifier}`);
assert.deepEqual(legacy.events, ['scrub', 'read-verifier', 'remove-verifier', 'navigate']);

for (const stored of [null, `${verifier}/recovery`, JSON.stringify(`${verifier}/PASSWORD_RECOVERY`), JSON.stringify(`${verifier}/recovery/extra`), JSON.stringify({ verifier }), JSON.stringify('short/recovery')]) {
  assert.equal(run({ search: '?code=sample-code', stored }).destination, undefined);
}
for (const input of [
  { search: '?code=a&code=b', stored: JSON.stringify(`${verifier}/recovery`) },
  { search: '?code=a&state=b', stored: JSON.stringify(`${verifier}/recovery`) },
  { search: '?code=a', hash: '#type=recovery&access_token=token', stored: JSON.stringify(`${verifier}/recovery`) },
  { hash: '#type=recovery&access_token=one&access_token=two' },
  { hash: '#type=signup&access_token=token' },
  { hash: '#type=recovery&access_token=token&error=denied' },
  { hash: '#type=recovery&access_token=token&expires_at=1' },
  { search: '?code=a', stored: JSON.stringify(`${verifier}/recovery`), storageError: true },
  { search: '?code=a', stored: JSON.stringify(`${verifier}/recovery`), removeError: true },
  {},
]) assert.equal(run(input).destination, undefined);
console.log('Recovery bridge native/PKCE, fixed destination, storage boundary and failure checks passed.');
