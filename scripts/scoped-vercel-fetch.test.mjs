import assert from 'node:assert/strict';
import test from 'node:test';
import { fetchApprovedVercelURL } from './scoped-vercel-fetch.mjs';

const approvedHosts = new Set([
  'brasstune.vercel.app',
  'brass-tune-preview-kelvis-prject.vercel.app',
]);
const isApprovedURL = (url) => approvedHosts.has(url.hostname);

function response(status, location = null) {
  return new Response('', {
    status,
    headers: location ? { Location: location } : {},
  });
}

test('fails closed before a Vercel bypass credential can cross an origin boundary', async () => {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url: url.toString(), headers: init.headers });
    return response(302, 'https://receiver.example.test/capture');
  };

  await assert.rejects(
    fetchApprovedVercelURL('https://brasstune.vercel.app/', {
      bypassSecret: 'test-only-secret',
      fetchImpl,
      isApprovedURL,
    }),
    /left the approved BrassTune hosts/,
  );
  assert.equal(requests.length, 1);
  assert.equal(requests[0].headers['x-vercel-protection-bypass'], 'test-only-secret');
  assert.equal(requests.some(({ url }) => url.includes('receiver.example.test')), false);
});

test('reattaches the bypass credential only after validating each approved redirect hop', async () => {
  const requests = [];
  const fetchImpl = async (url, init) => {
    requests.push({ url: url.toString(), headers: init.headers });
    if (requests.length === 1) {
      return response(307, 'https://brass-tune-preview-kelvis-prject.vercel.app/practice');
    }
    return response(200);
  };

  const result = await fetchApprovedVercelURL('https://brasstune.vercel.app/', {
    bypassSecret: 'test-only-secret',
    fetchImpl,
    isApprovedURL,
  });
  assert.equal(result.status, 200);
  assert.deepEqual(
    requests.map(({ url }) => url),
    [
      'https://brasstune.vercel.app/',
      'https://brass-tune-preview-kelvis-prject.vercel.app/practice',
    ],
  );
  assert.equal(
    requests.every(({ headers }) => headers['x-vercel-protection-bypass'] === 'test-only-secret'),
    true,
  );
});

test('rejects insecure redirects and caps approved redirect depth', async () => {
  await assert.rejects(
    fetchApprovedVercelURL('https://brasstune.vercel.app/', {
      bypassSecret: 'test-only-secret',
      fetchImpl: async () => response(302, 'http://brasstune.vercel.app/insecure'),
      isApprovedURL,
    }),
    /must use HTTPS/,
  );

  let requestCount = 0;
  await assert.rejects(
    fetchApprovedVercelURL('https://brasstune.vercel.app/', {
      fetchImpl: async () => {
        requestCount += 1;
        return response(302, '/loop');
      },
      isApprovedURL,
      maxRedirects: 2,
    }),
    /exceeded 2 hops/,
  );
  assert.equal(requestCount, 3);
});
