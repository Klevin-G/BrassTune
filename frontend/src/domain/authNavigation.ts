export const DEFAULT_AUTH_RETURN_PATH = '/home';
export const PENDING_AUTH_RETURN_KEY = 'brasstune.pendingAuthNext';

const CONTROL_CHARACTERS = /[\u0000-\u001f\u007f]/;
const ENCODED_CONTROL_OR_SLASH = /%(?:0[0-9a-f]|1[0-9a-f]|7f|2f|5c)/i;

function currentOrigin(): string {
  return typeof window === 'undefined' ? 'https://brasstune.local' : window.location.origin;
}

/**
 * Converts a candidate auth return target to a same-origin app path.
 * It rejects protocol-relative, backslash, control-character, credential, root,
 * and recursive auth destinations before a router ever sees them.
 */
export function safeReturnPath(
  value: string | null | undefined,
  origin = currentOrigin(),
): string {
  if (!value) return DEFAULT_AUTH_RETURN_PATH;
  const candidate = value.trim();
  if (
    !candidate
    || CONTROL_CHARACTERS.test(candidate)
    || candidate.includes('\\')
    || ENCODED_CONTROL_OR_SLASH.test(candidate)
  ) {
    return DEFAULT_AUTH_RETURN_PATH;
  }

  try {
    const base = new URL(origin);
    const parsed = new URL(candidate, base);
    const explicitlyRelative = candidate.startsWith('/') && !candidate.startsWith('//');
    const explicitlySameOrigin = /^[a-z][a-z\d+.-]*:/i.test(candidate) && parsed.origin === base.origin;
    if ((!explicitlyRelative && !explicitlySameOrigin) || parsed.origin !== base.origin || parsed.username || parsed.password) {
      return DEFAULT_AUTH_RETURN_PATH;
    }
    // URL normalization can turn an apparently single-slash relative target
    // such as `/..//host` into a protocol-relative-looking pathname. Never
    // hand that shape to a router or a later redirect boundary.
    if (
      parsed.pathname.startsWith('//')
      || parsed.pathname === '/'
      || parsed.pathname === '/auth'
      || parsed.pathname.startsWith('/auth/')
    ) {
      return DEFAULT_AUTH_RETURN_PATH;
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`;
  } catch {
    return DEFAULT_AUTH_RETURN_PATH;
  }
}

export function authPathWithReturn(
  path: '/auth/sign-in' | '/auth/sign-up' | '/auth/reset-password',
  next: string,
): string {
  return `${path}?next=${encodeURIComponent(safeReturnPath(next))}`;
}

export function gatewayPathWithReturn(next: string): string {
  return `/?next=${encodeURIComponent(safeReturnPath(next))}`;
}

export function passwordResetRedirectURL(next: string, origin = currentOrigin()): string {
  const redirect = new URL('/auth/reset-password', origin);
  redirect.searchParams.set('next', safeReturnPath(next, origin));
  return redirect.toString();
}

export function oauthCallbackRedirectURL(origin = currentOrigin()): string {
  return new URL('/auth/callback', new URL(origin).origin).toString();
}

export function rememberPendingAuthReturn(next: string): void {
  try {
    sessionStorage.setItem(PENDING_AUTH_RETURN_KEY, safeReturnPath(next));
  } catch {
    // The URL still carries the return path for the current auth flow.
  }
}

export function readPendingAuthReturn({ consume = false }: { consume?: boolean } = {}): string | null {
  try {
    const value = sessionStorage.getItem(PENDING_AUTH_RETURN_KEY);
    if (consume) sessionStorage.removeItem(PENDING_AUTH_RETURN_KEY);
    return value;
  } catch {
    return null;
  }
}

export function clearPendingAuthReturn(): void {
  try {
    sessionStorage.removeItem(PENDING_AUTH_RETURN_KEY);
  } catch {
    // Storage can be unavailable in privacy-restricted browsers.
  }
}
