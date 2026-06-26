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

  it('uses Render defaults on exact Vercel preview deployment hostnames', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-d99807eh3-aryaswebsites.vercel.app',
        hostname: 'brass-tune-d99807eh3-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/instruments')).toBe('https://brasstune.onrender.com/api/instruments');
    expect(await pitchWebSocketUrl()).toBe('wss://brasstune.onrender.com/ws/pitch');
  });

  it('never falls back to Vercel same-origin API paths from hosted origins', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'unrelated-preview.vercel.app',
        hostname: 'unrelated-preview.vercel.app',
      },
    });
    expect(exportUrl('/api/health')).toBe('https://brasstune.onrender.com/api/health');
    expect(await pitchWebSocketUrl()).toBe('wss://brasstune.onrender.com/ws/pitch');
  });

  it('uses Render defaults on the Vercel team alias', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-aryaswebsites.vercel.app',
        hostname: 'brass-tune-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/ready')).toBe('https://brasstune.onrender.com/api/ready');
    expect(await pitchWebSocketUrl()).toBe('wss://brasstune.onrender.com/ws/pitch');
  });

  it('keeps authorization headers when requests add upload headers', async () => {
    const { setAuthTokenProvider, uploadSessionAudio } = await loadClient('', 'https://api.example.test');
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ uploaded: true, audio: { id: 7 } }),
    });
    vi.stubGlobal('fetch', fetchMock);
    setAuthTokenProvider(async () => 'signed-in-token');

    await uploadSessionAudio(7, new Blob(['audio'], { type: 'audio/webm' }), 1.5);

    const [, init] = fetchMock.mock.calls[0];
    const headers = new Headers(init.headers);
    expect(headers.get('authorization')).toBe('Bearer signed-in-token');
    expect(headers.get('content-type')).toBe('audio/webm');
    expect(headers.get('x-audio-duration-seconds')).toBe('1.5');
  });
});
