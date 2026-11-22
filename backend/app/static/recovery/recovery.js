(() => {
  'use strict';

  const configNode = document.getElementById('recovery-public-config');
  const form = document.getElementById('recovery-form');
  const password = document.getElementById('password');
  const confirmation = document.getElementById('password-confirmation');
  const submit = document.getElementById('submit');
  const status = document.getElementById('status');
  const recoveryHash = location.hash;
  let recovery = null;
  let config = null;

  // Remove fragment credentials before showing UI or making any network call.
  history.replaceState(null, '', location.pathname);

  function showError(message) {
    recovery = null;
    form.hidden = true;
    status.textContent = message;
  }

  function readSingle(params, name, required = false) {
    const values = params.getAll(name);
    if (values.length > 1 || (required && values.length !== 1)) return null;
    return values.length === 1 ? values[0] : '';
  }

  function validOpaqueValue(value, minimum = 1, maximum = 16384) {
    return typeof value === 'string'
      && value.length >= minimum
      && value.length <= maximum
      && !/[\u0000-\u001f\u007f\s]/.test(value);
  }

  function validCodeVerifier(value) {
    return typeof value === 'string'
      && /^[A-Za-z0-9._~-]{43,128}$/.test(value);
  }

  try {
    config = JSON.parse(configNode.textContent || '');
  } catch {
    showError('Password recovery is unavailable right now. Request a new recovery email and try again later.');
    return;
  }
  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(config.supabaseUrl || '')
      || !/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(config.publishableKey || '')) {
    showError('Password recovery is unavailable right now. Request a new recovery email and try again later.');
    return;
  }

  const params = new URLSearchParams(recoveryHash.startsWith('#') ? recoveryHash.slice(1) : '');
  const implicitFields = new Set(['access_token', 'refresh_token', 'token_type', 'expires_in', 'expires_at', 'type']);
  const pkceFields = new Set(['code', 'code_verifier', 'type']);
  const parameterNames = [...params.keys()];
  const usesPKCE = parameterNames.includes('code') || parameterNames.includes('code_verifier');
  const allowed = usesPKCE ? pkceFields : implicitFields;
  if (!recoveryHash || parameterNames.some((key) => !allowed.has(key))
      || [...allowed].some((key) => params.getAll(key).length > 1)
      || params.has('error') || params.has('error_code') || params.has('error_description')) {
    showError('This recovery link is invalid. Request a new recovery email.');
    return;
  }
  const type = readSingle(params, 'type', true);
  if (type !== 'recovery') {
    showError('This recovery link is invalid or expired. Request a new recovery email.');
    return;
  }
  if (usesPKCE) {
    const code = readSingle(params, 'code', true);
    const verifier = readSingle(params, 'code_verifier', true);
    if (!validOpaqueValue(code, 1, 4096) || !validCodeVerifier(verifier)) {
      showError('This recovery link is invalid or expired. Request a new recovery email.');
      return;
    }
    recovery = { code, verifier };
  } else {
    const accessToken = readSingle(params, 'access_token', true);
    const tokenType = readSingle(params, 'token_type');
    const expiresAt = readSingle(params, 'expires_at');
    const refreshToken = readSingle(params, 'refresh_token');
    const expiresIn = readSingle(params, 'expires_in');
    if (!validOpaqueValue(accessToken)
        || (tokenType && tokenType.toLowerCase() !== 'bearer')
        || (refreshToken && !validOpaqueValue(refreshToken))
        || (expiresIn && !/^\d{1,10}$/.test(expiresIn))
        || (expiresAt && (!/^\d{1,13}$/.test(expiresAt) || Number(expiresAt) * 1000 <= Date.now()))) {
      showError('This recovery link is invalid or expired. Request a new recovery email.');
      return;
    }
    recovery = { accessToken };
  }
  function enablePasswordForm() {
    form.hidden = false;
    status.textContent = 'Choose a new password for your BrassTune account.';
  }

  async function exchangeRecoveryCode() {
    status.textContent = 'Checking your recovery link…';
    try {
      const exchange = await fetch(`${config.supabaseUrl}/auth/v1/token?grant_type=pkce`, {
        method: 'POST',
        mode: 'cors',
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        headers: {
          apikey: config.publishableKey,
          Authorization: `Bearer ${config.publishableKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ auth_code: recovery.code, code_verifier: recovery.verifier }),
      });
      if (!exchange.ok) {
        showError('This recovery link is invalid or expired. Request a new recovery email.');
        return;
      }
      const exchanged = await exchange.json().catch(() => null);
      const accessToken = exchanged && validOpaqueValue(exchanged.access_token) ? exchanged.access_token : null;
      if (!accessToken) {
        showError('This recovery link is invalid or expired. Request a new recovery email.');
        return;
      }
      recovery = { accessToken };
      enablePasswordForm();
    } catch {
      showError('Password recovery could not reach the account service. Request a new recovery email and try again.');
    }
  }

  if (recovery.code) {
    // Supabase PKCE authorization codes are short-lived and one-use. Exchange
    // before asking for a password, retaining only the resulting access token.
    void exchangeRecoveryCode();
  } else {
    enablePasswordForm();
  }

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (!recovery || !recovery.accessToken) {
      showError('This recovery link is invalid or expired. Request a new recovery email.');
      return;
    }
    if (password.value.length < 8 || password.value !== confirmation.value) {
      status.textContent = 'Use a password with at least 8 characters and enter it the same way twice.';
      return;
    }
    submit.disabled = true;
    status.textContent = 'Updating your password…';
    try {
      const response = await fetch(`${config.supabaseUrl}/auth/v1/user`, {
        method: 'PUT',
        mode: 'cors',
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        headers: {
          apikey: config.publishableKey,
          Authorization: `Bearer ${recovery.accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ password: password.value }),
      });
      password.value = '';
      confirmation.value = '';
      recovery = null;
      if (!response.ok) {
        showError('This recovery link is invalid or expired. Request a new recovery email.');
        return;
      }
      form.hidden = true;
      status.textContent = 'Your password was updated. Return to BrassTune and sign in.';
    } catch {
      password.value = '';
      confirmation.value = '';
      recovery = null;
      showError('Password recovery could not reach the account service. Request a new recovery email and try again.');
    } finally {
      password.value = '';
      confirmation.value = '';
      recovery = null;
      submit.disabled = false;
    }
  });
})();
