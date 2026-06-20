import { afterEach, describe, expect, it, vi } from 'vitest';

async function loadClient(wsBase = '', apiBase = '') {
  vi.resetModules();
  vi.stubEnv('VITE_WS_BASE_URL', wsBase);
  vi.stubEnv('VITE_API_BASE_URL', apiBase);
  return import('./client');
}

describe('API client runtime URLs', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it('falls back to current secure host for pitch WebSocket', async () => {
    const { pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', { location: { protocol: 'https:', host: 'app.example.test', hostname: 'app.example.test' } });
    expect(await pitchWebSocketUrl()).toBe('wss://app.example.test/ws/pitch');
  });

  it('keeps auth tokens out of the WebSocket URL', async () => {
    const { pitchWebSocketAuthPayload, pitchWebSocketUrl, setAuthTokenProvider } = await loadClient();
    vi.stubGlobal('window', { location: { protocol: 'http:', host: 'localhost:5173', hostname: 'localhost' } });
    setAuthTokenProvider(async () => 'dev-user-1');
    expect(await pitchWebSocketUrl()).toBe('ws://localhost:5173/ws/pitch');
    expect(await pitchWebSocketAuthPayload()).toEqual({ type: 'authenticate', token: 'dev-user-1' });
  });

  it('uses configured WebSocket base when provided', async () => {
    const { pitchWebSocketUrl } = await loadClient('wss://api.example.test');
    vi.stubGlobal('window', { location: { protocol: 'https:', host: 'app.example.test', hostname: 'app.example.test' } });
    expect(await pitchWebSocketUrl()).toBe('wss://api.example.test/ws/pitch');
  });

  it('uses Render defaults on Vercel-hosted deployments when Vite envs are absent', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app',
        hostname: 'brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/health')).toBe('https://brasstune.onrender.com/api/health');
    expect(await pitchWebSocketUrl()).toBe('wss://brasstune.onrender.com/ws/pitch');
  });

  it('does not silently use production Render from unknown hosted origins', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'unrelated-preview.vercel.app',
        hostname: 'unrelated-preview.vercel.app',
      },
    });
    expect(exportUrl('/api/health')).toBe('/api/health');
    expect(await pitchWebSocketUrl()).toBe('wss://unrelated-preview.vercel.app/ws/pitch');
  });
});
