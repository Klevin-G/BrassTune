import { describe, expect, it } from 'vitest';
import { passwordResetRedirectURL } from '../domain/authNavigation';
import { authPathWithNext, localizedOAuthError, safeAuthNext } from './AuthPage';

describe('auth navigation', () => {
  it('keeps protected route paths and query strings', () => {
    expect(safeAuthNext('/ensemble?join=BRASS123')).toBe('/ensemble?join=BRASS123');
    expect(authPathWithNext('/auth/sign-up', '/ensemble?join=BRASS123'))
      .toBe('/auth/sign-up?next=%2Fensemble%3Fjoin%3DBRASS123');
    expect(authPathWithNext('/auth/reset-password', '/sessions'))
      .toBe('/auth/reset-password?next=%2Fsessions');
  });

  it('fails closed for external, root, and recursive auth destinations', () => {
    for (const unsafe of [
      null,
      '',
      'https://example.com',
      '//example.com',
      '\\\\example.com/steal',
      '/%5c%5cexample.com/steal',
      '/%2f%2fexample.com/steal',
      '/ensemble%0d%0aSet-Cookie:bad',
      'javascript:alert(1)',
      '/',
      '/auth/callback',
      '/auth/sign-in?next=/ensemble',
    ]) {
      expect(safeAuthNext(unsafe)).toBe('/home');
    }
  });

  it('normalizes an explicit same-origin URL and rejects a different origin', () => {
    expect(safeAuthNext('https://brasstune.test/ensemble?join=BRASS#invite', 'https://brasstune.test'))
      .toBe('/ensemble?join=BRASS#invite');
    expect(safeAuthNext('https://brasstune.test.evil.example/ensemble', 'https://brasstune.test')).toBe('/home');
  });

  it('carries a validated return path in password-reset links that open in another tab', () => {
    const redirect = new URL(passwordResetRedirectURL('/ensemble?join=BRASS123', 'https://brasstune.test'));
    expect(redirect.origin).toBe('https://brasstune.test');
    expect(redirect.pathname).toBe('/auth/reset-password');
    expect(redirect.searchParams.get('next')).toBe('/ensemble?join=BRASS123');

    const malformed = new URL(passwordResetRedirectURL('//evil.example/steal', 'https://brasstune.test'));
    expect(malformed.searchParams.get('next')).toBe('/home');
  });

  it('maps OAuth failures to localized stable messages instead of raw provider text', () => {
    const t = ((id: string) => `localized:${id}`) as never;
    expect(localizedOAuthError(new Error('popup closed by user'), t, 'auth.googleFailure')).toBe('localized:auth.errorCancelled');
    expect(localizedOAuthError(new Error('provider internal stack'), t, 'auth.appleFailure')).toBe('localized:auth.appleFailure');
  });
});
