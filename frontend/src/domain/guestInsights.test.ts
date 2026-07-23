import { afterEach, describe, expect, it } from 'vitest';
import { nextDemoPitchFrame } from './demoPitch';
import { buildGuestHeatmap, buildGuestNoteStats, buildGuestPracticePlan, buildGuestProgress, buildGuestRecommendations } from './guestInsights';
import { GUEST_WORKSPACE_ACCESS, clearGuestSessions, createGuestSession, saveGuestSessionFromFrames } from './guestSessions';

describe('guest insights', () => {
  afterEach(() => {
    clearGuestSessions(GUEST_WORKSPACE_ACCESS);
  });

  it('builds analytics, coach, and progress from guest sessions saved in the browser', () => {
    const draft = createGuestSession('trumpet', 440, 'Local take');
    const frames = Array.from({ length: 80 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440));
    saveGuestSessionFromFrames(draft, frames);

    const stats = buildGuestNoteStats('trumpet');
    const recommendations = buildGuestRecommendations(stats);
    const plan = buildGuestPracticePlan(stats, 'trumpet');
    const progress = buildGuestProgress('trumpet', stats);

    expect(stats.length).toBeGreaterThan(0);
    expect(stats[0].recommendation_summary).toMatch(/centered|sharp|flat|inconsistent/i);
    expect(recommendations[0].explanation).toMatch(/guest sessions stored in this browser/i);
    expect(plan?.title).toBe('Guest intonation plan');
    expect(plan?.focus_notes.length).toBeGreaterThan(0);
    expect(progress.session_count).toBe(1);
    expect(progress.period?.current).toBe('Guest browser data');
    expect(progress.worst_notes.length).toBeGreaterThan(0);
    expect(buildGuestHeatmap('trumpet', stats).some((row) => row.has_data === false)).toBe(true);
  });

  it('keeps guest insight aggregation scoped to the selected instrument', () => {
    saveGuestSessionFromFrames(
      createGuestSession('trumpet', 440, 'Trumpet take'),
      Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440)),
    );
    saveGuestSessionFromFrames(
      createGuestSession('trombone', 440, 'Trombone take'),
      Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trombone', 440)),
    );

    expect(buildGuestProgress('trumpet', buildGuestNoteStats('trumpet')).session_count).toBe(1);
    expect(buildGuestProgress('horn', buildGuestNoteStats('horn')).session_count).toBe(0);
  });

  it('filters guest analytics by date range and ignores malformed local rows', () => {
    const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'localStorage');
    const store = new Map<string, string>();
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      value: {
        getItem: (key: string) => store.get(key) ?? null,
        setItem: (key: string, value: string) => store.set(key, value),
        removeItem: (key: string) => store.delete(key),
      },
    });
    store.set('brasstune.guestSessions.v1', JSON.stringify([{ id: -1 }, null, 'broken']));
    try {
      expect(buildGuestNoteStats('trumpet')).toEqual([]);

      saveGuestSessionFromFrames(
        { ...createGuestSession('trumpet', 440, 'Old take'), started_at: '2026-06-01T00:00:00.000Z', created_at: '2026-06-01T00:00:00.000Z' },
        Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440)),
      );
      saveGuestSessionFromFrames(
        { ...createGuestSession('trumpet', 440, 'New take'), started_at: '2026-07-01T00:00:00.000Z', created_at: '2026-07-01T00:00:00.000Z' },
        Array.from({ length: 24 }, (_, index) => nextDemoPitchFrame(index, 'trumpet', 440)),
      );

      expect(buildGuestNoteStats('trumpet', { date_from: '2026-06-30' }).length).toBeGreaterThan(0);
      expect(buildGuestProgress('trumpet', buildGuestNoteStats('trumpet')).session_count).toBe(2);
    } finally {
      if (originalDescriptor) {
        Object.defineProperty(globalThis, 'localStorage', originalDescriptor);
      } else {
        delete (globalThis as { localStorage?: Storage }).localStorage;
      }
    }
  });
});
