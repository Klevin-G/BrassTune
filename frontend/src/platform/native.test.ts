import { describe, expect, it } from 'vitest';
import { hasValidNativeAccountEndpoints, nativeOAuthCallbackRoute } from './native';

describe('native OAuth callback routing', () => {
  it('keeps only the expected custom-scheme callback and its query or fragment', () => {
    expect(nativeOAuthCallbackRoute(
      'com.brasstune.android://auth/callback?code=one-time-code&state=expected#ignored',
    )).toBe('/auth/callback?code=one-time-code&state=expected#ignored');
  });

  it('rejects lookalike, credential-bearing, and malformed URLs', () => {
    for (const value of [
      'com.brasstune.android://other/callback?code=code',
      'com.brasstune.android://auth/other?code=code',
      'com.brasstune.android://user@auth/callback?code=code',
      'https://auth/callback?code=code',
      'not a url',
    ]) {
      expect(nativeOAuthCallbackRoute(value)).toBeNull();
    }
  });
});

describe('native account endpoint gate', () => {
  it('requires exact secure API and WebSocket origins', () => {
    expect(hasValidNativeAccountEndpoints(
      'https://api.brasstune.example',
      'wss://api.brasstune.example',
    )).toBe(true);
  });

  it('rejects missing, local, credential-bearing, path, and wrong-protocol endpoints', () => {
    for (const [api, ws] of [
      ['', 'wss://api.brasstune.example'],
      ['http://api.brasstune.example', 'wss://api.brasstune.example'],
      ['https://user:password@api.brasstune.example', 'wss://api.brasstune.example'],
      ['https://api.brasstune.example/api', 'wss://api.brasstune.example'],
      ['https://api.brasstune.example', 'https://api.brasstune.example'],
      ['https://localhost', 'wss://localhost'],
      ['https://127.0.0.1', 'wss://127.0.0.1'],
    ]) {
      expect(hasValidNativeAccountEndpoints(api, ws)).toBe(false);
    }
  });
});
