import { execFileSync } from 'node:child_process';

const relevantPrefixes = [
  '.github/workflows/backend.yml',
  '.github/workflows/deploy.yml',
  '.github/workflows/frontend.yml',
  '.github/workflows/production-smoke.yml',
  '.github/workflows/render-keepalive.yml',
  '.github/workflows/security.yml',
  'backend/',
  'fixtures/',
  'frontend/',
  'render.yaml',
  'scripts/hosted-smoke.mjs',
  'supabase/',
  'vercel.json',
];

const ignoredPrefixes = [
  'swift/',
  'docs/release-readiness/APP_',
  'docs/release-readiness/IOS_',
  'docs/release-readiness/TESTFLIGHT_',
];

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function changedFiles() {
  const head = process.env.VERCEL_GIT_COMMIT_SHA || git(['rev-parse', 'HEAD']);
  const previous = process.env.VERCEL_GIT_PREVIOUS_SHA || '';
  let base = previous;
  if (!base || /^0+$/.test(base)) {
    base = git(['rev-list', '--max-parents=0', head]);
  }
  try {
    const mergeBase = git(['merge-base', base, head]);
    base = mergeBase || base;
  } catch {
    // Fall through to the previous SHA; Vercel should build if diffing is ambiguous.
  }
  const output = git(['diff', '--name-only', `${base}...${head}`]);
  return output ? output.split(/\r?\n/).filter(Boolean) : [];
}

function isRelevant(path) {
  return relevantPrefixes.some((prefix) => path === prefix || path.startsWith(prefix));
}

function isIgnoredOnly(path) {
  return ignoredPrefixes.some((prefix) => path === prefix || path.startsWith(prefix));
}

try {
  const files = changedFiles();
  if (files.length === 0) {
    console.log('No changed files detected; continue Vercel build.');
    process.exit(1);
  }
  const relevant = files.filter(isRelevant);
  if (relevant.length > 0) {
    console.log(`Web-relevant changes detected: ${relevant.join(', ')}`);
    process.exit(1);
  }
  if (files.every(isIgnoredOnly)) {
    console.log(`Ignoring Vercel build for native-only changes: ${files.join(', ')}`);
    process.exit(0);
  }
  console.log(`No web deployment files changed: ${files.join(', ')}`);
  process.exit(0);
} catch (error) {
  console.error(`Could not determine changed files; continue Vercel build. ${error.message}`);
  process.exit(1);
}
