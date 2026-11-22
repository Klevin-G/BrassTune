// Retires the previous app worker without touching visitor data or forcing a reload.
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
const oauthFields = new Set(['code', 'state', 'error', 'error_code', 'error_description', 'access_token', 'refresh_token', 'token_hash', 'type', 'expires_in', 'expires_at', 'token_type', 'provider_token', 'provider_refresh_token']);
const query = new URLSearchParams(location.search);
const fragment = new URLSearchParams(location.hash.slice(1));
const removeOAuthFields = (params) => {
  let changed = false;
  for (const field of oauthFields) {
    if (params.has(field)) { params.delete(field); changed = true; }
  }
  return changed;
};
const queryChanged = removeOAuthFields(query);
const fragmentChanged = removeOAuthFields(fragment);
if (queryChanged || fragmentChanged) {
  const safeQuery = query.size ? `?${query}` : '';
  const safeFragment = fragment.size ? `#${fragment}` : '';
  history.replaceState(null, '', `${location.pathname}${safeQuery}${safeFragment}`);
}
