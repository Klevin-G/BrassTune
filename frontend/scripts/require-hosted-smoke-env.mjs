const required = ['E2E_BASE_URL', 'E2E_API_BASE_URL', 'E2E_WS_BASE_URL'];

for (const name of required) {
  const value = process.env[name];
  if (!value) {
    console.error(`Set ${name} before running hosted smoke tests.`);
    process.exit(1);
  }
}

const checks = [
  ['E2E_BASE_URL', 'https:'],
  ['E2E_API_BASE_URL', 'https:'],
  ['E2E_WS_BASE_URL', 'wss:'],
];

for (const [name, protocol] of checks) {
  const url = new URL(process.env[name]);
  if (url.protocol !== protocol) {
    console.error(`${name} must use ${protocol}.`);
    process.exit(1);
  }
  if (['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
    console.error(`${name} must not point at a local host for hosted smoke.`);
    process.exit(1);
  }
}

if (process.env.E2E_VERCEL_SHARE_URL) {
  const url = new URL(process.env.E2E_VERCEL_SHARE_URL);
  if (url.protocol !== 'https:') {
    console.error('E2E_VERCEL_SHARE_URL must use https:.');
    process.exit(1);
  }
}
