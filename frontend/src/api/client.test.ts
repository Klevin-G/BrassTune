import { afterEach, describe, expect, it, vi } from 'vitest';
import { pitchWebSocketUrl, setAuthTokenProvider } from './client';

describe('API client runtime URLs', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    setAuthTokenProvider(null);
  });

  it('falls back to current secure host for pitch WebSocket', async () => {
    vi.stubGlobal('window', { location: { protocol: 'https:', host: 'app.example.test' } });
    expect(await pitchWebSocketUrl()).toBe('wss://app.example.test/ws/pitch');
  });

  it('passes auth token through the WebSocket query string', async () => {
    vi.stubGlobal('window', { location: { protocol: 'http:', host: 'localhost:5173' } });
    setAuthTokenProvider(async () => 'dev-user-1');
    expect(await pitchWebSocketUrl()).toBe('ws://localhost:5173/ws/pitch?token=dev-user-1');
  });
});
