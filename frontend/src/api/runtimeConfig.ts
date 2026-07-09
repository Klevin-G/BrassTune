const CONFIGURED_API_BASE = import.meta.env.VITE_API_BASE_URL ?? '';
const CONFIGURED_WS_BASE = import.meta.env.VITE_WS_BASE_URL ?? '';

// Sentinel returned when no base can be resolved in a hosted/production build.
// Callers must treat this as "no backend configured" instead of silently
// falling back to localhost or the static same-origin host.
export const UNRESOLVED_BASE = 'unavailable';

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
  // On our own Vercel deployment (production, preview, or a *.vercel.app host)
  // the backend is served same-origin under /api via the vercel.json service
  // rewrite, so use a relative base. Set VITE_API_BASE_URL to override (e.g. to
  // point the frontend at a separately hosted backend such as Render).
  if (isKnownBrassTuneHostedOrigin() || isVercelHostedOrigin()) return '';
  // Unknown origin: same-origin ('') is only acceptable during local development.
  // In a production build we must never silently hit an unconfigured host.
  return import.meta.env.PROD ? UNRESOLVED_BASE : '';
}

export function wsBase() {
  if (CONFIGURED_WS_BASE) return cleanBase(CONFIGURED_WS_BASE);
  const base = apiBase();
  if (base === UNRESOLVED_BASE) return UNRESOLVED_BASE;
  return base ? base.replace(/^http/, 'ws') : '';
}

export function isApiBaseResolved(base = apiBase()) {
  return base !== UNRESOLVED_BASE;
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
