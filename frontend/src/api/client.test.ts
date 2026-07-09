import { afterEach, describe, expect, it, vi } from 'vitest';
import type { PitchFrame } from '../domain/types';

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

  it('uses same-origin /api on Vercel git preview deployments (vercel.json rewrite)', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app',
        hostname: 'brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/health')).toBe('/api/health');
    expect(await pitchWebSocketUrl()).toBe('wss://brass-tune-git-arya-release-readiness-hardening-aryaswebsites.vercel.app/ws/pitch');
  });

  it('uses same-origin /api on exact Vercel preview deployment hostnames', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-d99807eh3-aryaswebsites.vercel.app',
        hostname: 'brass-tune-d99807eh3-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/instruments')).toBe('/api/instruments');
    expect(await pitchWebSocketUrl()).toBe('wss://brass-tune-d99807eh3-aryaswebsites.vercel.app/ws/pitch');
  });

  it('uses same-origin /api on any of its vercel.app hosts', async () => {
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

  it('uses same-origin /api on the Vercel team alias', async () => {
    const { exportUrl, pitchWebSocketUrl } = await loadClient();
    vi.stubGlobal('window', {
      location: {
        protocol: 'https:',
        host: 'brass-tune-aryaswebsites.vercel.app',
        hostname: 'brass-tune-aryaswebsites.vercel.app',
      },
    });
    expect(exportUrl('/api/ready')).toBe('/api/ready');
    expect(await pitchWebSocketUrl()).toBe('wss://brass-tune-aryaswebsites.vercel.app/ws/pitch');
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

  it('splits pitch frame saves into backend-safe batches', async () => {
    const { recordPitchFramesInBatches } = await loadClient('', 'https://api.example.test');
    const fetchMock = vi.fn().mockImplementation(async (_url, init) => ({
      ok: true,
      json: async () => ({ saved: JSON.parse(String(init.body)).length, rejected: 0 }),
    }));
    vi.stubGlobal('fetch', fetchMock);
    const frames: PitchFrame[] = Array.from({ length: 2500 }, (_, index) => ({
      timestamp_ms: index,
      frequency_hz: 440,
      instrument_id: 'trumpet',
      reference_pitch_hz: 440,
      is_valid_for_recording: true,
      confidence: 0.9,
      rms: 0.2,
      midi_note_float: 69,
      nearest_midi: 69,
      concert_note_name: 'A',
      concert_octave: 4,
      written_note_name: 'B',
      written_octave: 4,
      cents_deviation: 0,
      tuning_status: 'in_tune',
      detector_source: 'browser_local_pitch',
    }));

    const result = await recordPitchFramesInBatches(42, frames);

    expect(fetchMock).toHaveBeenCalledTimes(3);
    expect(result).toEqual({ saved: 2500, rejected: 0, attempted: 2500 });
    const payloadSizes = fetchMock.mock.calls.map(([, init]) => JSON.parse(String(init.body)).length);
    expect(payloadSizes).toEqual([1000, 1000, 500]);
  });

  it('reports rejected pitch frames from successful batch responses', async () => {
    const { recordPitchFramesInBatches } = await loadClient('', 'https://api.example.test');
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ saved: 3, rejected: 1 }),
    }));
    const frames = Array.from({ length: 4 }, (_, index) => ({
      timestamp_ms: index,
      frequency_hz: 440,
      instrument_id: 'trumpet',
      reference_pitch_hz: 440,
      is_valid_for_recording: true,
      confidence: 0.9,
      rms: 0.2,
      midi_note_float: 69,
      nearest_midi: 69,
      concert_note_name: 'A',
      concert_octave: 4,
      written_note_name: 'B',
      written_octave: 4,
      cents_deviation: 0,
      tuning_status: 'in_tune',
      detector_source: 'browser_local_pitch',
    })) as PitchFrame[];

    await expect(recordPitchFramesInBatches(42, frames, { batchSize: 4 })).resolves.toEqual({ saved: 3, rejected: 1, attempted: 4 });
  });

  it('attaches partial batch progress when a later pitch-frame batch fails', async () => {
    const { recordPitchFramesInBatches } = await loadClient('', 'https://api.example.test');
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ saved: 2, rejected: 0 }) })
      .mockResolvedValueOnce({ ok: false, text: async () => JSON.stringify({ detail: 'temporary outage' }) });
    vi.stubGlobal('fetch', fetchMock);
    const frames = Array.from({ length: 4 }, (_, index) => ({
      timestamp_ms: index,
      frequency_hz: 440,
      instrument_id: 'trumpet',
      reference_pitch_hz: 440,
      is_valid_for_recording: true,
      confidence: 0.9,
      rms: 0.2,
      midi_note_float: 69,
      nearest_midi: 69,
      concert_note_name: 'A',
      concert_octave: 4,
      written_note_name: 'B',
      written_octave: 4,
      cents_deviation: 0,
      tuning_status: 'in_tune',
      detector_source: 'browser_local_pitch',
    })) as PitchFrame[];

    await expect(recordPitchFramesInBatches(42, frames, { batchSize: 2 })).rejects.toMatchObject({
      saved: 2,
      rejected: 0,
      attempted: 2,
      failedFrames: frames.slice(2),
    });
  });
});
