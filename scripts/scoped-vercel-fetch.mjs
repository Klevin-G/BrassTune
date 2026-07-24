const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const BYPASS_HEADER = 'x-vercel-protection-bypass';

function assertApprovedHTTPSURL(url, isApprovedURL) {
  if (url.protocol !== 'https:') {
    throw new Error(`Vercel access redirect must use HTTPS: ${url.origin}`);
  }
  if (!isApprovedURL(url)) {
    throw new Error(`Vercel access redirect left the approved BrassTune hosts: ${url.hostname}`);
  }
}

export async function fetchApprovedVercelURL(
  startURL,
  {
    bypassSecret = '',
    fetchImpl = fetch,
    isApprovedURL,
    maxRedirects = 5,
  },
) {
  let currentURL = new URL(startURL);
  for (let redirectCount = 0; redirectCount <= maxRedirects; redirectCount += 1) {
    assertApprovedHTTPSURL(currentURL, isApprovedURL);
    const headers = bypassSecret ? { [BYPASS_HEADER]: bypassSecret } : {};
    const response = await fetchImpl(currentURL, { redirect: 'manual', headers });
    if (!REDIRECT_STATUSES.has(response.status)) return response;

    const location = response.headers.get('location');
    if (!location) {
      throw new Error(`Vercel access redirect returned HTTP ${response.status} without Location`);
    }
    if (redirectCount === maxRedirects) {
      throw new Error(`Vercel access redirect exceeded ${maxRedirects} hops`);
    }
    const nextURL = new URL(location, currentURL);
    assertApprovedHTTPSURL(nextURL, isApprovedURL);
    await response.body?.cancel();
    currentURL = nextURL;
  }
  throw new Error('Vercel access redirect could not be resolved');
}
