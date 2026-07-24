import { afterEach, describe, expect, it } from 'vitest';
import { nextDemoPitchFrame } from './demoPitch';
import {
  GUEST_WORKSPACE_ACCESS,
  clearGuestSessions,
  createGuestSession,
  deleteGuestSession,
  getGuestSession,
  guestSessionsExport,
  isGeneratedGuestSessionName,
  listGuestSessions,
  saveGuestSessionFromFrames,
} from './guestSessions';

describe('guest session storage', () => {
  afterEach(() => {
    clearGuestSessions(GUEST_WORKSPACE_ACCESS);
  });

  it('identifies only automatic English guest labels for presentation-time localization', () => {
    expect(isGeneratedGuestSessionName('Guest practice 7/23/2026')).toBe(true);
    expect(isGeneratedGuestSessionName('Practice 7/23/2026')).toBe(true);
    expect(isGeneratedGuestSessionName('My warmup')).toBe(false);
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
    expect(saved.recommendations[0]?.message).toMatch(/guest workspace/i);
    expect(getGuestSession(saved.id, GUEST_WORKSPACE_ACCESS)?.name).toBe('Guest take');
    expect(listGuestSessions(GUEST_WORKSPACE_ACCESS)).toHaveLength(1);
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
      expect(listGuestSessions(GUEST_WORKSPACE_ACCESS)).toHaveLength(0);
    } finally {
      if (originalDescriptor) {
        Object.defineProperty(globalThis, 'localStorage', originalDescriptor);
      } else {
        delete (globalThis as { localStorage?: Storage }).localStorage;
      }
    }
  });

  it('fails closed outside the explicit guest workspace for list, direct review, export, delete, and clear', () => {
    const saved = saveGuestSessionFromFrames(
      createGuestSession('trumpet', 440, 'Private guest take'),
      Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440)),
    );

    expect(listGuestSessions()).toEqual([]);
    expect(getGuestSession(saved.id)).toBeNull();
    expect(JSON.parse(guestSessionsExport()).sessions).toEqual([]);
    expect(deleteGuestSession(saved.id)).toBe(false);
    expect(clearGuestSessions()).toBe(false);
    expect(listGuestSessions(GUEST_WORKSPACE_ACCESS)).toHaveLength(1);
    expect(getGuestSession(saved.id, GUEST_WORKSPACE_ACCESS)?.name).toBe('Private guest take');
    expect(getGuestSession(Math.abs(saved.id), GUEST_WORKSPACE_ACCESS)).toBeNull();
    expect(JSON.parse(guestSessionsExport(GUEST_WORKSPACE_ACCESS)).sessions).toHaveLength(1);
  });

  it('clears all guest recordings only through the guest workspace capability', () => {
    saveGuestSessionFromFrames(
      createGuestSession('trumpet', 440, 'One'),
      Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440)),
    );
    saveGuestSessionFromFrames(
      createGuestSession('trombone', 440, 'Two'),
      Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trombone', 440)),
    );
    expect(listGuestSessions(GUEST_WORKSPACE_ACCESS)).toHaveLength(2);
    expect(clearGuestSessions(GUEST_WORKSPACE_ACCESS)).toBe(true);
    expect(listGuestSessions(GUEST_WORKSPACE_ACCESS)).toEqual([]);
  });
});
