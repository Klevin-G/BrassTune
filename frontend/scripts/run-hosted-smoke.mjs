import { spawnSync } from 'node:child_process';

const aliases = new Map([
  ['E2E_BASE_URL', 'BRASSTUNE_WEB_BASE_URL'],
  ['E2E_VERCEL_SHARE_URL', 'BRASSTUNE_WEB_ACCESS_URL'],
  ['E2E_API_BASE_URL', 'BRASSTUNE_API_BASE_URL'],
  ['E2E_WS_BASE_URL', 'BRASSTUNE_WS_BASE_URL'],
]);

const env = { ...process.env, E2E_START_LOCAL_SERVERS: '0' };

for (const [target, source] of aliases) {
  if (!env[target] && env[source]) {
    env[target] = env[source];
  }
}

const required = ['E2E_BASE_URL', 'E2E_API_BASE_URL', 'E2E_WS_BASE_URL'];

for (const name of required) {
  const value = env[name];
  if (!value) {
    const alias = aliases.get(name);
    console.error(`Set ${name}${alias ? ` or ${alias}` : ''} before running hosted smoke tests.`);
    process.exit(1);
  }
}

const checks = [
  ['E2E_BASE_URL', 'https:'],
  ['E2E_API_BASE_URL', 'https:'],
  ['E2E_WS_BASE_URL', 'wss:'],
];

for (const [name, protocol] of checks) {
  const url = new URL(env[name]);
  if (url.protocol !== protocol) {
    console.error(`${name} must use ${protocol}.`);
    process.exit(1);
  }
  if (['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
    console.error(`${name} must not point at a local host for hosted smoke.`);
    process.exit(1);
  }
}

if (env.E2E_VERCEL_SHARE_URL) {
  const url = new URL(env.E2E_VERCEL_SHARE_URL);
  if (url.protocol !== 'https:') {
    console.error('E2E_VERCEL_SHARE_URL must use https:.');
    process.exit(1);
  }
}

const result = spawnSync(
  'npx',
  ['playwright', 'test', 'e2e/hosted-smoke.spec.ts', ...process.argv.slice(2)],
  {
    env,
    shell: process.platform === 'win32',
    stdio: 'inherit',
  },
);

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

process.exit(result.status ?? 1);
