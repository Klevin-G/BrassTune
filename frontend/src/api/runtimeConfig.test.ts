import { describe, expect, it } from 'vitest';
import { defaultApiBase, isKnownBrassTuneHostedOrigin, UNRESOLVED_BASE } from './runtimeConfig';

describe('runtime backend fallback', () => {
  it('allows only documented BrassTune production and preview hosts', () => {
    expect(isKnownBrassTuneHostedOrigin('brasstune.vercel.app')).toBe(true);
    expect(isKnownBrassTuneHostedOrigin('brass-tune-abc123-kelvis-prject.vercel.app')).toBe(true);
    expect(isKnownBrassTuneHostedOrigin('attacker-preview.vercel.app')).toBe(false);
    expect(isKnownBrassTuneHostedOrigin('brasstune.vercel.app.evil.example')).toBe(false);
  });

  it('fails closed for arbitrary production Vercel hosts', () => {
    expect(defaultApiBase('brasstune.vercel.app', true)).toBe('https://brasstune-u8qj.onrender.com');
    expect(defaultApiBase('unrelated.vercel.app', true)).toBe(UNRESOLVED_BASE);
    expect(defaultApiBase('localhost', false)).toBe('');
  });
});
