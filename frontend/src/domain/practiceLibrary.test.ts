import { describe, expect, it } from 'vitest';
import {
  PRACTICE_LIBRARY_VERSION,
  currentWeekKey,
  emptyPracticeLibrary,
  normalizeMetronomePreset,
  ownerPracticeKey,
  parseExerciseNotes,
  parsePracticeLibrary,
  resolvePracticeOwner,
  writePracticeLibrary,
} from './practiceLibrary';

describe('practice library storage', () => {
  it('isolates guest and account keys and keeps an unresolved account out of guest storage', () => {
    expect(ownerPracticeKey('guest')).not.toBe(ownerPracticeKey('account:42'));
    expect(resolvePracticeOwner({ loading: true, hasAuthSession: false, isSignedIn: false })).toBeNull();
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: true, isSignedIn: false })).toBeNull();
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: true, isSignedIn: true, profileId: 42 })).toBe('account:42');
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: false, isSignedIn: false })).toBe('guest');
  });

  it('recovers from corrupt data, resets an old weekly goal, and bounds persisted labels', () => {
    expect(parsePracticeLibrary('{broken')).toMatchObject({ version: PRACTICE_LIBRARY_VERSION, customExercises: [] });
    const raw = JSON.stringify({
      ...emptyPracticeLibrary(new Date('2026-07-13T12:00:00')),
      favorites: [{ kind: 'warmup', id: 'x'.repeat(200), label: 'y'.repeat(200), href: `/${'z'.repeat(400)}` }],
      weeklyGoal: { week: '2020-01-01', targetMinutes: 500, completedMinutes: 499 },
    });
    const parsed = parsePracticeLibrary(raw, new Date('2026-07-16T12:00:00'));
    expect(parsed.favorites[0].id).toHaveLength(80);
    expect(parsed.favorites[0].label).toHaveLength(80);
    expect(parsed.favorites[0].href.length).toBeLessThanOrEqual(240);
    expect(parsed.weeklyGoal).toEqual({ week: currentWeekKey(new Date('2026-07-16T12:00:00')), targetMinutes: 60, completedMinutes: 0 });
  });

  it('retries a quota failure with bounded optional history', () => {
    let calls = 0;
    let saved = '';
    const storage = { setItem: (_key: string, value: string) => { calls += 1; if (calls === 1) throw new Error('quota'); saved = value; } };
    const library = emptyPracticeLibrary();
    library.recents = Array.from({ length: 8 }, (_, index) => ({ kind: 'warmup', id: String(index), label: String(index), href: '/practice' }));
    library.reflections = Array.from({ length: 20 }, (_, index) => ({ id: String(index), text: 'note', createdAt: new Date().toISOString() }));
    expect(writePracticeLibrary(storage, 'guest', library)).toBe(true);
    expect(calls).toBe(2);
    expect(JSON.parse(saved).recents).toHaveLength(3);
    expect(JSON.parse(saved).reflections).toHaveLength(10);
  });
});

describe('practice inputs', () => {
  it('accepts 1–32 written notes and rejects invalid or oversized lists', () => {
    expect(parseExerciseNotes('C F# B♭')).toEqual({ notes: ['C', 'F#', 'Bb'], error: null });
    expect(parseExerciseNotes('')).toMatchObject({ notes: [], error: expect.any(String) });
    expect(parseExerciseNotes('C nope')).toMatchObject({ notes: [], error: expect.any(String) });
    expect(parseExerciseNotes(Array.from({ length: 33 }, () => 'C').join(' '))).toMatchObject({ notes: [], error: expect.any(String) });
  });

  it('clamps metronome presets', () => {
    expect(normalizeMetronomePreset({ id: 'p', name: ' Fast ', bpm: 999, numerator: 0, denominator: 3, subdivision: 'triplet', accentDownbeat: true, countIn: false })).toMatchObject({ name: 'Fast', bpm: 300, numerator: 1, denominator: 4, subdivision: 'triplet', countIn: false });
  });
});
