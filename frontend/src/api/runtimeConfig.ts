const HOSTED_RENDER_API_BASE = 'https://brasstune-u8qj.onrender.com';
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
  // brasstune.vercel.app is the one canonical production domain. Vercel preview
  // deploys are auto-named from the project (brass-tune-*-kelvis-prject.vercel.app);
  // they still resolve to the backend via isVercelHostedOrigin() below.
  return (
    hostname === 'brasstune.vercel.app' ||
    /^brass-tune-[a-z0-9-]+-kelvis-prject\.vercel\.app$/i.test(hostname)
  );
}

export function isVercelHostedOrigin(hostname = currentHostname()) {
  return hostname.endsWith('.vercel.app');
}

export function defaultApiBase(hostname: string, production: boolean) {
  if (isKnownBrassTuneHostedOrigin(hostname)) return HOSTED_RENDER_API_BASE;
  return production ? UNRESOLVED_BASE : '';
}

export function apiBase() {
  if (CONFIGURED_API_BASE) return cleanBase(CONFIGURED_API_BASE);
  // The frontend (Vercel) calls the Render backend cross-origin. VITE_API_BASE_URL
  // is the primary source (baked at build time); this hosted default is a safety net
  // so a Vercel production/preview build still reaches the backend if the env is absent.
  // Unknown origins, including unrelated *.vercel.app deployments, must never
  // inherit the BrassTune backend. Same-origin ('') is local-development only.
  return defaultApiBase(currentHostname(), import.meta.env.PROD);
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
    usingVercelHostedFallback: !CONFIGURED_API_BASE && isKnownBrassTuneHostedOrigin(),
    hostname: currentHostname(),
  };
}
