import { afterEach, describe, expect, it } from 'vitest';
import { nextDemoPitchFrame } from './demoPitch';
import { clearGuestSessions, createGuestSession, getGuestSession, listGuestSessions, saveGuestSessionFromFrames } from './guestSessions';

describe('guest session storage', () => {
  afterEach(() => {
    clearGuestSessions();
  });

  it('saves a reviewable local guest session from browser pitch frames', () => {
    const draft = createGuestSession('trumpet', 440, 'Guest take');
    const frames = Array.from({ length: 80 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440));
    const saved = saveGuestSessionFromFrames(draft, frames);

    expect(saved.id).toBeLessThan(0);
    expect(saved.guest_session).toBe(true);
    expect(saved.samples_count).toBeGreaterThan(0);
    expect(saved.note_events.length).toBeGreaterThan(0);
    expect(saved.note_stats.length).toBeGreaterThan(0);
    expect(saved.recommendations[0]?.message).toMatch(/guest take|guest session|guest practice/i);
    expect(getGuestSession(saved.id)?.name).toBe('Guest take');
    expect(listGuestSessions()).toHaveLength(1);
  });

  it('stores guest audio metadata without requiring cloud upload', () => {
    const draft = createGuestSession('trombone', 442, 'Guest audio');
    const saved = saveGuestSessionFromFrames(draft, [nextDemoPitchFrame(0, 'trombone', 442)], {
      dataUrl: 'data:audio/wav;base64,UklGRg==',
      mimeType: 'audio/wav',
      durationSeconds: 3,
      sizeBytes: 44,
    });

    expect(saved.audio_available).toBe(true);
    expect(saved.audio_mime_type).toBe('audio/wav');
    expect(saved.audio_duration_seconds).toBe(3);
    expect(saved.audio_size_bytes).toBe(44);
    expect(saved.guest_audio_data_url).toContain('data:audio/wav');
  });

  it('does not return a saved session when browser storage rejects the write', () => {
    const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      value: {
        getItem: () => null,
        setItem: () => {
          throw new DOMException('Guest storage quota exceeded.', 'QuotaExceededError');
        },
        removeItem: () => undefined,
      },
    });

    try {
      const draft = createGuestSession('trumpet', 440, 'Quota take');
      expect(() => saveGuestSessionFromFrames(draft, [nextDemoPitchFrame(0, 'trumpet', 440)])).toThrow(/quota/i);
      expect(listGuestSessions()).toHaveLength(0);
    } finally {
      if (originalDescriptor) {
        Object.defineProperty(globalThis, 'localStorage', originalDescriptor);
      } else {
        delete (globalThis as { localStorage?: Storage }).localStorage;
      }
    }
  });
});
