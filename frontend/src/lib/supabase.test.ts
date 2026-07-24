import { describe, expect, it } from 'vitest';
import { resolveAuthProviders, supabaseClientOptions } from './supabase';

describe('Supabase web auth configuration', () => {
  it('uses PKCE with persistent callback detection for browser OAuth', () => {
    expect(supabaseClientOptions).toEqual({
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        flowType: 'pkce',
      },
    });
  });

  it('keeps each social provider unavailable until its explicit deployment flag is enabled', () => {
    expect(resolveAuthProviders({})).toEqual({ google: false, apple: false });
    expect(resolveAuthProviders({ VITE_AUTH_GOOGLE_ENABLED: 'true' }))
      .toEqual({ google: true, apple: false });
    expect(resolveAuthProviders({ VITE_SUPABASE_APPLE_ENABLED: 'true' }))
      .toEqual({ google: false, apple: true });
    expect(resolveAuthProviders({
      VITE_SUPABASE_GOOGLE_ENABLED: 'true',
      VITE_AUTH_APPLE_ENABLED: 'true',
    })).toEqual({ google: true, apple: true });
  });
});
