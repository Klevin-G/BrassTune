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
    for (const unsafe of [null, '', 'https://example.com', '//example.com', '/', '/auth/callback']) {
      expect(safeAuthNext(unsafe)).toBe('/home');
    }
  });
});
