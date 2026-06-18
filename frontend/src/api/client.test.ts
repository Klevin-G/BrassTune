import { afterEach, describe, expect, it, vi } from 'vitest';

async function loadClient(wsBase = '') {
  vi.resetModules();
  vi.stubEnv('VITE_WS_BASE_URL', wsBase);
  return import('./client');
}

describe('API client runtime URLs', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('falls back to current secure host for pitch WebSocket', async () => {
    const { pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', { location: { protocol: 'https:', host: 'app.example.test' } });
    expect(await pitchWebSocketUrl()).toBe('wss://app.example.test/ws/pitch');
  });

  it('passes auth token through the WebSocket query string', async () => {
    const { pitchWebSocketUrl, setAuthTokenProvider } = await loadClient();
    vi.stubGlobal('window', { location: { protocol: 'http:', host: 'localhost:5173' } });
    setAuthTokenProvider(async () => 'dev-user-1');
    expect(await pitchWebSocketUrl()).toBe('ws://localhost:5173/ws/pitch?token=dev-user-1');
  });

  it('uses configured WebSocket base when provided', async () => {
    const { pitchWebSocketUrl } = await loadClient('wss://api.example.test');
    vi.stubGlobal('window', { location: { protocol: 'https:', host: 'app.example.test' } });
    expect(await pitchWebSocketUrl()).toBe('wss://api.example.test/ws/pitch');
  });
});
