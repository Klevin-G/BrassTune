const HOSTED_RENDER_API_BASE = 'https://brasstune.onrender.com';
const CONFIGURED_API_BASE = import.meta.env.VITE_API_BASE_URL ?? '';
const CONFIGURED_WS_BASE = import.meta.env.VITE_WS_BASE_URL ?? '';

function cleanBase(base: string) {
  return base.replace(/\/+$/, '');
}

function currentHostname() {
  if (typeof window === 'undefined') return '';
  return window.location.hostname || window.location.host.split(':')[0];
}

export function isKnownBrassTuneHostedOrigin(hostname = currentHostname()) {
  return (
    hostname === 'brass-tune.vercel.app' ||
    hostname === 'brass-tune-aryaswebsites.vercel.app' ||
    /^brass-tune-git-[a-z0-9-]+-aryaswebsites\.vercel\.app$/i.test(hostname) ||
    /^brass-tune-[a-z0-9]+-aryaswebsites\.vercel\.app$/i.test(hostname)
  );
}

export function isVercelHostedOrigin(hostname = currentHostname()) {
  return hostname.endsWith('.vercel.app');
}

export function apiBase() {
  if (CONFIGURED_API_BASE) return cleanBase(CONFIGURED_API_BASE);
  return isKnownBrassTuneHostedOrigin() || isVercelHostedOrigin() ? HOSTED_RENDER_API_BASE : '';
}

export function wsBase() {
  if (CONFIGURED_WS_BASE) return cleanBase(CONFIGURED_WS_BASE);
  const base = apiBase();
  return base ? base.replace(/^http/, 'ws') : '';
}

export function runtimeDiagnostics() {
  return {
    apiConfigured: Boolean(CONFIGURED_API_BASE),
    wsConfigured: Boolean(CONFIGURED_WS_BASE),
    usingKnownHostedFallback: !CONFIGURED_API_BASE && isKnownBrassTuneHostedOrigin(),
    usingVercelHostedFallback: !CONFIGURED_API_BASE && isVercelHostedOrigin(),
    hostname: currentHostname(),
  };
}
