import crypto from 'node:crypto';
import net from 'node:net';
import tls from 'node:tls';

const DEFAULT_WEB_BASE_URL = 'https://brass-tune.vercel.app';
const DEFAULT_API_BASE_URL = 'https://brasstune-u8qj.onrender.com';
const DEFAULT_WS_BASE_URL = 'wss://brasstune-u8qj.onrender.com';
const APPROVED_RENDER_HOST = 'brasstune-u8qj.onrender.com';
const APPROVED_VERCEL_HOSTS = new Set([
  'brass-tune.vercel.app',
  'brass-tune-aryaswebsites.vercel.app',
]);

const webBaseURL = cleanBase(process.env.BRASSTUNE_WEB_BASE_URL || DEFAULT_WEB_BASE_URL);
const webAccessURL = process.env.BRASSTUNE_WEB_ACCESS_URL || urlWithPath(webBaseURL, '/');
const apiBaseURL = cleanBase(process.env.BRASSTUNE_API_BASE_URL || DEFAULT_API_BASE_URL);
const wsBaseURL = cleanBase(process.env.BRASSTUNE_WS_BASE_URL || DEFAULT_WS_BASE_URL);
const liveAuth = process.env.E2E_LIVE_AUTH === '1';
const authToken = process.env.BRASSTUNE_WS_AUTH_TOKEN || process.env.BRASSTUNE_AUTH_TOKEN || '';
const vercelBypassSecret = process.env.BRASSTUNE_VERCEL_AUTOMATION_BYPASS_SECRET || process.env.VERCEL_AUTOMATION_BYPASS_SECRET || '';
const expectedSHA = process.env.BRASSTUNE_EXPECTED_BACKEND_SHA
  || (process.env.BRASSTUNE_ENFORCE_EXPECTED_SHA === '1' ? (process.env.BRASSTUNE_EXPECTED_SHA || process.env.GITHUB_SHA || '') : '');

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

function isApprovedVercelHost(hostname) {
  return APPROVED_VERCEL_HOSTS.has(hostname)
    || (hostname.startsWith('brass-tune-') && hostname.endsWith('-aryaswebsites.vercel.app'));
}

function assertApprovedSecretDestination(label, value, type) {
  const url = new URL(value);
  if (type === 'vercel' && !isApprovedVercelHost(url.hostname)) {
    throw new Error(`${label} is not an approved BrassTune Vercel host: ${url.hostname}`);
  }
  if (type === 'render' && url.hostname !== APPROVED_RENDER_HOST) {
    throw new Error(`${label} is not the approved Render backend host: ${url.hostname}`);
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
  if (vercelBypassSecret) {
    assertApprovedSecretDestination('BRASSTUNE_WEB_ACCESS_URL', webAccessURL, 'vercel');
  }
  const headers = vercelBypassSecret ? { 'x-vercel-protection-bypass': vercelBypassSecret } : {};
  const response = await fetch(webAccessURL, { redirect: 'follow', headers });
  const text = await response.text();
  const finalURL = new URL(response.url);
  if (
    response.status === 401
    || response.status === 403
    || finalURL.hostname === 'vercel.com'
    || finalURL.hostname.endsWith('.vercel.com')
    || /vercel authentication|single sign-on|log in to vercel|continue with sso/i.test(text)
  ) {
    throw new Error(`web app is protected by Vercel auth/SSO: HTTP ${response.status}`);
  }
  if (!response.ok) {
    throw new Error(`web root returned HTTP ${response.status}`);
  }
  if (!/BrassTune|root|<html/i.test(text)) {
    throw new Error('web root did not return the expected app shell');
  }
}

async function checkReadiness() {
  const response = await fetch(urlWithPath(apiBaseURL, '/api/ready'), {
    headers: { Origin: webBaseURL },
  });
  if (!response.ok) throw new Error(`/api/ready returned HTTP ${response.status}: ${await response.text()}`);
  const body = await response.json();
  if (body.ok !== true) throw new Error('/api/ready did not report ok=true');
  if (body.database_backend !== 'postgresql') {
    throw new Error(`/api/ready reported database_backend=${body.database_backend}, expected postgresql`);
  }
}

async function checkVersion() {
  const response = await fetch(urlWithPath(apiBaseURL, '/api/version'), {
    headers: { Origin: webBaseURL },
  });
  if (!response.ok) throw new Error(`/api/version returned HTTP ${response.status}`);
  const body = await response.json();
  if (!body.commit_sha) throw new Error('/api/version did not include commit_sha');
  if (expectedSHA && body.commit_sha !== expectedSHA) {
    throw new Error(`/api/version commit_sha ${body.commit_sha} did not match expected ${expectedSHA}`);
  }
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
  if (liveAuth && !authToken) {
    throw new Error('E2E_LIVE_AUTH=1 requires BRASSTUNE_WS_AUTH_TOKEN or BRASSTUNE_AUTH_TOKEN');
  }
  const outcome = await rawWebSocketProbe(
    urlWithPath(wsBaseURL, '/ws/pitch'),
    webBaseURL,
    liveAuth ? { type: 'authenticate', token: authToken } : { type: 'ping' },
  );
  if (outcome.status !== 101 || !outcome.frameText) {
    throw new Error(`WebSocket did not produce an app-level message: ${JSON.stringify(outcome)}`);
  }
  let payload;
  try {
    payload = JSON.parse(outcome.frameText);
  } catch {
    throw new Error(`WebSocket returned non-JSON payload: ${outcome.frameText}`);
  }
  if (liveAuth) {
    if (payload.type !== 'authenticated' && payload.type !== 'pong') {
      throw new Error(`live WebSocket auth did not succeed: ${outcome.frameText}`);
    }
    return;
  }
  const expectedGuestMessages = [
    'Authenticate before sending pitch frames.',
    'pong',
  ];
  if (payload.type !== 'pong' && !expectedGuestMessages.includes(payload.message)) {
    throw new Error(`unexpected unauthenticated WebSocket message: ${outcome.frameText}`);
  }
}

function encodeClientTextFrame(text) {
  const payload = Buffer.from(text, 'utf8');
  const mask = crypto.randomBytes(4);
  let header;
  if (payload.length < 126) {
    header = Buffer.from([0x81, 0x80 | payload.length]);
  } else if (payload.length <= 0xffff) {
    header = Buffer.alloc(4);
    header[0] = 0x81;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(payload.length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x81;
    header[1] = 0x80 | 127;
    header.writeUInt32BE(0, 2);
    header.writeUInt32BE(payload.length, 6);
  }
  const masked = Buffer.alloc(payload.length);
  for (let index = 0; index < payload.length; index += 1) {
    masked[index] = payload[index] ^ mask[index % 4];
  }
  return Buffer.concat([header, mask, masked]);
}

function decodeServerTextFrame(buffer) {
  if (buffer.length < 2) return '';
  const opcode = buffer[0] & 0x0f;
  if (opcode !== 1) return '';
  let length = buffer[1] & 0x7f;
  let offset = 2;
  if (length === 126) {
    if (buffer.length < 4) return '';
    length = buffer.readUInt16BE(2);
    offset = 4;
  } else if (length === 127) {
    if (buffer.length < 10) return '';
    const high = buffer.readUInt32BE(2);
    const low = buffer.readUInt32BE(6);
    if (high !== 0 || low > 1024 * 1024) return '';
    length = low;
    offset = 10;
  }
  if (buffer.length < offset + length) return '';
  return buffer.subarray(offset, offset + length).toString('utf8');
}

async function rawWebSocketProbe(wsURL, origin, message = null) {
  const url = new URL(wsURL);
  const secure = url.protocol === 'wss:';
  const port = Number(url.port || (secure ? 443 : 80));
  const key = crypto.randomBytes(16).toString('base64');
  const requestPath = `${url.pathname || '/'}${url.search}`;
  const request = [
    `GET ${requestPath} HTTP/1.1`,
    `Host: ${url.host}`,
    'Connection: Upgrade',
    'Upgrade: websocket',
    'Sec-WebSocket-Version: 13',
    `Sec-WebSocket-Key: ${key}`,
    `Origin: ${origin}`,
    '',
    '',
  ].join('\r\n');

  return await new Promise((resolve, reject) => {
    const socket = secure
      ? tls.connect({ host: url.hostname, port, servername: url.hostname })
      : net.connect({ host: url.hostname, port });
    let buffer = Buffer.alloc(0);
    let sentMessage = false;
    const timer = setTimeout(() => {
      socket.destroy();
      reject(new Error(`WebSocket probe timed out for ${wsURL}`));
    }, 10000);
    socket.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    socket.once('connect', () => {
      socket.write(request);
    });
    socket.on('data', (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd === -1) return;
      const headerText = buffer.subarray(0, headerEnd).toString('utf8');
      const statusLine = headerText.split('\r\n')[0] || '';
      const status = Number(statusLine.match(/^HTTP\/\d(?:\.\d)?\s+(\d+)/)?.[1] || 0);
      const frameText = decodeServerTextFrame(buffer.subarray(headerEnd + 4));
      if (status !== 101 || frameText) {
        clearTimeout(timer);
        socket.destroy();
        resolve({ status, statusLine, frameText });
        return;
      }
      if (message && !sentMessage) {
        sentMessage = true;
        socket.write(encodeClientTextFrame(JSON.stringify(message)));
      }
    });
    socket.on('close', () => {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd !== -1) {
        const headerText = buffer.subarray(0, headerEnd).toString('utf8');
        const statusLine = headerText.split('\r\n')[0] || '';
        const status = Number(statusLine.match(/^HTTP\/\d(?:\.\d)?\s+(\d+)/)?.[1] || 0);
        resolve({ status, statusLine, frameText: decodeServerTextFrame(buffer.subarray(headerEnd + 4)) });
      }
    });
  });
}

async function checkWebSocketQueryTokenRejected() {
  const outcome = await rawWebSocketProbe(urlWithPath(wsBaseURL, '/ws/pitch?token=dev-user-1'), webBaseURL);
  if (!/query-token auth is disabled/i.test(outcome.frameText || '')) {
    throw new Error(`WebSocket query-token auth was not explicitly rejected: ${JSON.stringify(outcome)}`);
  }
}

async function checkWebSocketBadOriginRejected() {
  const outcome = await rawWebSocketProbe(urlWithPath(wsBaseURL, '/ws/pitch'), 'https://evil.example');
  if (outcome.status === 101 && !/origin is not allowed/i.test(outcome.frameText || '')) {
    throw new Error(`WebSocket bad origin was not rejected: ${JSON.stringify(outcome)}`);
  }
}

try {
  assertHostedURL('BRASSTUNE_WEB_BASE_URL', webBaseURL, 'https:');
  assertHostedURL('BRASSTUNE_WEB_ACCESS_URL', webAccessURL, 'https:');
  assertHostedURL('BRASSTUNE_API_BASE_URL', apiBaseURL, 'https:');
  assertHostedURL('BRASSTUNE_WS_BASE_URL', wsBaseURL, 'wss:');
  assertApprovedSecretDestination('BRASSTUNE_API_BASE_URL', apiBaseURL, 'render');
  assertApprovedSecretDestination('BRASSTUNE_WS_BASE_URL', wsBaseURL, 'render');
} catch (error) {
  console.error(`FAIL configuration - ${error.message}`);
  process.exit(1);
}

await checkHTTP('web root loads', checkWebRoot);
await checkHTTP('Render /api/ready', checkReadiness);
await checkHTTP('Render /api/version', checkVersion);
await checkHTTP('CORS /api/ready', () => checkCORS('/api/ready'));
await checkHTTP('CORS /api/sessions/start', () => checkCORS('/api/sessions/start'));
await checkHTTP('WebSocket /ws/pitch app-level response', checkWebSocket);
await checkHTTP('WebSocket rejects query-token auth', checkWebSocketQueryTokenRejected);
await checkHTTP('WebSocket rejects bad Origin', checkWebSocketBadOriginRejected);

const failed = results.filter((result) => result.status === 'fail').length;
if (failed > 0) {
  console.error(`Hosted smoke failed: ${failed} check(s) failed.`);
  process.exit(1);
}
console.log('Hosted smoke passed.');
