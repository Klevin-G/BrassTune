const DEFAULT_API_BASE_URL = 'https://brasstune.onrender.com';
const apiBaseURL = cleanBase(process.env.BRASSTUNE_API_BASE_URL || DEFAULT_API_BASE_URL);
const expectedSHA = process.env.BRASSTUNE_EXPECTED_BACKEND_SHA || process.env.GITHUB_SHA || '';
const timeoutMs = positiveInt(process.env.BRASSTUNE_RELEASE_WAIT_TIMEOUT_MS, 10 * 60 * 1000);
const intervalMs = positiveInt(process.env.BRASSTUNE_RELEASE_WAIT_INTERVAL_MS, 15 * 1000);

function cleanBase(value) {
  return value.replace(/\/+$/, '');
}

function positiveInt(value, fallback) {
  const parsed = Number.parseInt(value || '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function urlWithPath(base, path) {
  return new URL(path, `${base}/`).toString();
}

async function fetchJSON(path) {
  const response = await fetch(urlWithPath(apiBaseURL, path), {
    headers: { Accept: 'application/json' },
  });
  const text = await response.text();
  let body = {};
  try {
    body = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${path} returned non-JSON HTTP ${response.status}: ${text.slice(0, 200)}`);
  }
  if (!response.ok) {
    throw new Error(`${path} returned HTTP ${response.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

async function releaseIsReady() {
  const version = await fetchJSON('/api/version');
  if (!version.commit_sha) {
    throw new Error('/api/version did not include commit_sha');
  }
  if (expectedSHA && version.commit_sha !== expectedSHA) {
    throw new Error(`/api/version commit_sha ${version.commit_sha} did not match expected ${expectedSHA}`);
  }
  const ready = await fetchJSON('/api/ready');
  if (ready.ok !== true) {
    throw new Error(`/api/ready did not report ok=true: ${JSON.stringify(ready)}`);
  }
  return { version, ready };
}

const deadline = Date.now() + timeoutMs;
let lastError = null;

while (Date.now() < deadline) {
  try {
    const result = await releaseIsReady();
    console.log(`Backend release ready at ${apiBaseURL}: ${result.version.commit_sha}`);
    process.exit(0);
  } catch (error) {
    lastError = error;
    console.log(`Waiting for backend release: ${error.message}`);
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
}

throw new Error(`Timed out waiting for backend release at ${apiBaseURL}: ${lastError?.message || 'no response'}`);
