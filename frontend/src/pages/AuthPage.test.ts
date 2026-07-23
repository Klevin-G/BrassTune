import { describe, expect, it } from 'vitest';
import { authPathWithNext, safeAuthNext } from './AuthPage';

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
});
