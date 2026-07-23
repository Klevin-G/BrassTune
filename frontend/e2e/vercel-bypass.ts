import type { Page, Route } from 'playwright/test';

const bypassHeader = 'x-vercel-protection-bypass';
const canonicalVercelURL = 'https://brasstune.vercel.app';

function isApprovedBrassTuneVercelHost(hostname: string) {
  return hostname === 'brasstune.vercel.app'
    || (hostname.startsWith('brass-tune-') && hostname.endsWith('-kelvis-prject.vercel.app'));
}

/**
 * Accept only the canonical production origin and validated BrassTune deployment
 * origins.  The hosted-smoke launcher performs the same validation before it
 * starts Playwright; this second check prevents a direct Playwright invocation
 * from widening where a Vercel bypass credential may travel.
 */
export function approvedBrassTuneVercelOrigins(...candidateURLs: Array<string | undefined>) {
  const origins = new Set<string>();
  for (const candidate of [canonicalVercelURL, ...candidateURLs]) {
    if (!candidate) continue;
    try {
      const url = new URL(candidate);
      if (url.protocol === 'https:' && !url.port && isApprovedBrassTuneVercelHost(url.hostname)) {
        origins.add(url.origin);
      }
    } catch {
      // Environment validation supplies the actionable error; do not grant a
      // bypass header to an unparsable candidate here.
    }
  }
  return origins;
}

export function scopedVercelBypassHeaders(
  requestURL: string,
  requestHeaders: Record<string, string>,
  bypassSecret: string,
  approvedOrigins: ReadonlySet<string>,
) {
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(requestHeaders)) {
    if (name.toLowerCase() !== bypassHeader) headers[name] = value;
  }

  try {
    if (approvedOrigins.has(new URL(requestURL).origin)) {
      headers[bypassHeader] = bypassSecret;
    }
  } catch {
    // Continue without the credential for non-HTTP/non-URL requests.
  }
  return headers;
}

/** Install before navigation. This only affects browser requests from `page`;
 * Playwright APIRequestContext and browser WebSockets do not inherit this
 * route handler or the bypass credential. */
export async function installScopedVercelBypass(
  page: Page,
  bypassSecret: string,
  approvedOrigins: ReadonlySet<string>,
) {
  await page.route('**/*', async (route: Route) => {
    await route.continue({
      headers: scopedVercelBypassHeaders(route.request().url(), route.request().headers(), bypassSecret, approvedOrigins),
    });
  });
}
