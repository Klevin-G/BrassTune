(() => {
  const destination = 'https://brasstune-u8qj.onrender.com/auth/reset-password';
  const verifierKey = 'sb-yznziwewxrlwnwiynlvl-auth-token-code-verifier';
  const status = document.getElementById('recovery-status');
  const search = location.search;
  const hash = location.hash;
  const fail = () => {
    status.textContent = 'This recovery link could not be opened. Request a new password reset from the BrassTune app, or contact support.';
  };
  try {
    // Scrub credentials before reading storage or opening the account service.
    history.replaceState(null, '', location.pathname);
    if (search.length + hash.length > 32768) return fail();
    const query = new URLSearchParams(search);
    const fragment = new URLSearchParams(hash.replace(/^#/, ''));
    const forwarded = new URLSearchParams({ type: 'recovery' });
    const opaque = (value, max) => typeof value === 'string' && value.length > 0
      && value.length <= max && !/[\s\u0000-\u001f\u007f]/.test(value);

    if (query.has('code')) {
      // auth-js 2.108.2 stores a JSON string suffixed with /recovery.
      if (query.getAll('code').length !== 1 || fragment.size
          || [...query.keys()].some((key) => !['code', 'next'].includes(key))
          || !opaque(query.get('code'), 4096)) return fail();
      const stored = JSON.parse(localStorage.getItem(verifierKey));
      const match = typeof stored === 'string' && stored.match(/^([A-Za-z0-9._~-]{43,128})\/recovery$/);
      if (!match) return fail();
      forwarded.set('code', query.get('code'));
      forwarded.set('code_verifier', match[1]);
      localStorage.removeItem(verifierKey);
    } else {
      const allowed = new Set(['access_token', 'refresh_token', 'token_type', 'expires_in', 'expires_at', 'type']);
      if ([...query.keys()].some((key) => key !== 'next')
          || [...fragment.keys()].some((key) => !allowed.has(key))
          || [...allowed].some((key) => fragment.getAll(key).length > 1)
          || fragment.get('type') !== 'recovery'
          || !opaque(fragment.get('access_token'), 16384)
          || (fragment.has('refresh_token') && !opaque(fragment.get('refresh_token'), 16384))
          || (fragment.has('token_type') && fragment.get('token_type').toLowerCase() !== 'bearer')
          || (fragment.has('expires_in') && !/^\d{1,10}$/.test(fragment.get('expires_in')))
          || (fragment.has('expires_at') && (!/^\d{1,13}$/.test(fragment.get('expires_at'))
            || Number(fragment.get('expires_at')) * 1000 <= Date.now()))) return fail();
      // The account service needs only the access token; never transfer refresh tokens.
      forwarded.set('access_token', fragment.get('access_token'));
    }
    location.replace(`${destination}#${forwarded}`);
  } catch {
    fail();
  }
})();
