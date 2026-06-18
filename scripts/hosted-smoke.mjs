const DEFAULT_WEB_BASE_URL = 'https://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app';
const DEFAULT_API_BASE_URL = 'https://brasstune.onrender.com';
const DEFAULT_WS_BASE_URL = 'wss://brasstune.onrender.com';

const webBaseURL = cleanBase(process.env.BRASSTUNE_WEB_BASE_URL || DEFAULT_WEB_BASE_URL);
const webAccessURL = process.env.BRASSTUNE_WEB_ACCESS_URL || urlWithPath(webBaseURL, '/');
const apiBaseURL = cleanBase(process.env.BRASSTUNE_API_BASE_URL || DEFAULT_API_BASE_URL);
const wsBaseURL = cleanBase(process.env.BRASSTUNE_WS_BASE_URL || DEFAULT_WS_BASE_URL);
const liveAuth = process.env.E2E_LIVE_AUTH === '1';
const authToken = process.env.BRASSTUNE_WS_AUTH_TOKEN || process.env.BRASSTUNE_AUTH_TOKEN || '';

const results = [];

function cleanBase(value) {
  return value.replace(/\/+$/, '');
}

function urlWithPath(base, path) {
  return new URL(path, `${base}/`).toString();
}

function assertHostedURL(label, value, expectedProtocol) {
  const url = new URL(value);
  if (url.hostname === 'localhost' || url.hostname === '127.0.0.1' || url.hostname === '[::1]') {
    throw new Error(`${label} must not point to localhost: ${url.origin}`);
  }
  if (expectedProtocol && url.protocol !== expectedProtocol) {
    throw new Error(`${label} must use ${expectedProtocol}: ${url.origin}`);
  }
}

function record(name, status, detail) {
  results.push({ name, status, detail });
  const marker = status === 'pass' ? 'PASS' : status === 'skip' ? 'SKIP' : 'FAIL';
  console.log(`${marker} ${name}${detail ? ` - ${detail}` : ''}`);
}

async function checkHTTP(name, fn) {
  try {
    await fn();
    record(name, 'pass');
  } catch (error) {
    record(name, 'fail', error.message);
    process.exitCode = 1;
  }
}

async function checkWebRoot() {
  const response = await fetch(webAccessURL, { redirect: 'follow' });
  const text = await response.text();
  if (response.status === 401 || response.status === 403 || /vercel authentication|single sign-on/i.test(text)) {
    throw new Error(`web app is protected by Vercel auth/SSO: HTTP ${response.status}`);
  }
  if (!response.ok) {
    throw new Error(`web root returned HTTP ${response.status}`);
  }
  if (!/BrassTune|root|<html/i.test(text)) {
    throw new Error('web root did not return the expected app shell');
  }
}

async function checkHealth() {
  const response = await fetch(urlWithPath(apiBaseURL, '/api/health'), {
    headers: { Origin: webBaseURL },
  });
  if (!response.ok) throw new Error(`/api/health returned HTTP ${response.status}`);
  const body = await response.json();
  if (body.ok !== true) throw new Error('/api/health did not report ok=true');
}

async function checkCORS(path) {
  const response = await fetch(urlWithPath(apiBaseURL, path), {
    method: 'OPTIONS',
    headers: {
      Origin: webBaseURL,
      'Access-Control-Request-Method': path.includes('sessions') ? 'POST' : 'GET',
      'Access-Control-Request-Headers': 'content-type,authorization',
    },
  });
  if (!response.ok) throw new Error(`${path} CORS preflight returned HTTP ${response.status}`);
  const allowOrigin = response.headers.get('access-control-allow-origin');
  if (allowOrigin !== webBaseURL) {
    throw new Error(`${path} CORS allow-origin was ${allowOrigin || 'missing'}, expected ${webBaseURL}`);
  }
}

async function checkWebSocket() {
  const wsURL = urlWithPath(wsBaseURL, '/ws/pitch');
  if (liveAuth && !authToken) {
    throw new Error('E2E_LIVE_AUTH=1 requires BRASSTUNE_WS_AUTH_TOKEN or BRASSTUNE_AUTH_TOKEN');
  }
  const outcome = await new Promise((resolve) => {
    const ws = new WebSocket(wsURL);
    let opened = false;
    const timer = setTimeout(() => {
      try {
        ws.close(1000, 'smoke timeout');
      } catch {}
      resolve({ type: 'timeout', opened });
    }, 10000);
    ws.addEventListener('open', () => {
      opened = true;
      ws.send(JSON.stringify(liveAuth ? { type: 'authenticate', token: authToken } : { type: 'ping' }));
    });
    ws.addEventListener('message', (event) => {
      clearTimeout(timer);
      try {
        ws.close(1000, 'smoke complete');
      } catch {}
      resolve({ type: 'message', data: String(event.data), opened });
    });
    ws.addEventListener('close', (event) => {
      clearTimeout(timer);
      resolve({ type: 'close', code: event.code, reason: event.reason, opened });
    });
    ws.addEventListener('error', () => {
      if (!opened) {
        clearTimeout(timer);
        resolve({ type: 'error', opened });
      }
    });
  });

  if (outcome.type !== 'message') {
    throw new Error(`WebSocket did not produce an app-level message: ${JSON.stringify(outcome)}`);
  }
  let payload;
  try {
    payload = JSON.parse(outcome.data);
  } catch {
    throw new Error(`WebSocket returned non-JSON payload: ${outcome.data}`);
  }
  if (liveAuth) {
    if (payload.type !== 'authenticated' && payload.type !== 'pong') {
      throw new Error(`live WebSocket auth did not succeed: ${outcome.data}`);
    }
    return;
  }
  const expectedGuestMessages = [
    'Authenticate before sending pitch frames.',
    'pong',
  ];
  if (payload.type !== 'pong' && !expectedGuestMessages.includes(payload.message)) {
    throw new Error(`unexpected unauthenticated WebSocket message: ${outcome.data}`);
  }
}

try {
  assertHostedURL('BRASSTUNE_WEB_BASE_URL', webBaseURL, 'https:');
  assertHostedURL('BRASSTUNE_WEB_ACCESS_URL', webAccessURL, 'https:');
  assertHostedURL('BRASSTUNE_API_BASE_URL', apiBaseURL, 'https:');
  assertHostedURL('BRASSTUNE_WS_BASE_URL', wsBaseURL, 'wss:');
} catch (error) {
  console.error(`FAIL configuration - ${error.message}`);
  process.exit(1);
}

await checkHTTP('web root loads', checkWebRoot);
await checkHTTP('Render /api/health', checkHealth);
await checkHTTP('CORS /api/health', () => checkCORS('/api/health'));
await checkHTTP('CORS /api/sessions/start', () => checkCORS('/api/sessions/start'));
await checkHTTP('WebSocket /ws/pitch app-level response', checkWebSocket);

const failed = results.filter((result) => result.status === 'fail').length;
if (failed > 0) {
  console.error(`Hosted smoke failed: ${failed} check(s) failed.`);
  process.exit(1);
}
console.log('Hosted smoke passed.');
