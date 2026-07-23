import { describe, expect, it } from 'vitest';
import {
  PRACTICE_LIBRARY_VERSION,
  BUILT_IN_PRACTICE_PACKS,
  claimSavedPracticeSessionMinutes,
  clearAccountPracticeState,
  currentWeekKey,
  emptyPracticeLibrary,
  normalizeMetronomePreset,
  millisecondsUntilNextPracticeWeek,
  ownerPracticeKey,
  ownerWorkspaceKey,
  parseExerciseNotes,
  parsePracticeLibrary,
  reconcilePracticeLibraryWeek,
  recordPracticeActivity,
  resolvePracticeOwner,
  removeCustomExercise,
  removeMetronomePreset,
  upsertCustomExercise,
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

  it('recovers from corrupt data, rolls weekly completion over, carries targets, and bounds persisted labels', () => {
    expect(parsePracticeLibrary('{broken')).toMatchObject({ version: PRACTICE_LIBRARY_VERSION, customExercises: [] });
    const raw = JSON.stringify({
      ...emptyPracticeLibrary(new Date('2026-07-13T12:00:00')),
      favorites: [{ kind: 'warmup', id: 'x'.repeat(200), label: 'y'.repeat(200), href: `/${'z'.repeat(400)}` }],
      weeklyGoal: { week: '2020-01-01', targetMinutes: 500, completedMinutes: 499, targetSessions: 12, completedSessions: 11 },
    });
    const parsed = parsePracticeLibrary(raw, new Date('2026-07-16T12:00:00'));
    expect(parsed.favorites[0].id).toHaveLength(80);
    expect(parsed.favorites[0].label).toHaveLength(80);
    expect(parsed.favorites[0].href.length).toBeLessThanOrEqual(240);
    expect(parsed.weeklyGoal).toEqual({ week: currentWeekKey(new Date('2026-07-16T12:00:00')), targetMinutes: 500, completedMinutes: 0, targetSessions: 12, completedSessions: 0 });
  });

  it('uses canonical limits for 60-character exercise names and ten recents', () => {
    const raw = JSON.stringify({
      ...emptyPracticeLibrary(),
      customExercises: [{ id: 'custom', name: 'x'.repeat(61), notes: ['A', 'G'], source: 'custom', createdAt: new Date().toISOString() }],
      recents: Array.from({ length: 12 }, (_, index) => ({ kind: 'warmup', id: String(index), label: `Recent ${index}`, href: '/practice' })),
    });
    const parsed = parsePracticeLibrary(raw);
    expect(parsed.customExercises[0].name).toHaveLength(60);
    expect(parsed.customExercises[0].notes).toEqual(['A', 'G']);
    expect(parsed.recents).toHaveLength(10);
    expect(parsed.weeklyGoal).toMatchObject({ targetMinutes: 60, targetSessions: 3, completedMinutes: 0, completedSessions: 0 });
  });

  it('reconciles a stale open-provider week before recording its first new-week activity', () => {
    // This is the in-memory provider path, rather than a fresh storage read:
    // a tab that remained open through Monday must not add to last week.
    const library = emptyPracticeLibrary(new Date('2026-07-19T23:59:00'));
    library.weeklyGoal = {
      week: '2026-07-13',
      targetMinutes: 180,
      completedMinutes: 75,
      targetSessions: 5,
      completedSessions: 3,
    };

    const recorded = recordPracticeActivity(library, 12, new Date('2026-07-20T00:01:00'));
    expect(recorded.weeklyGoal).toEqual({
      week: '2026-07-20',
      targetMinutes: 180,
      completedMinutes: 12,
      targetSessions: 5,
      completedSessions: 1,
    });
  });

  it('reconciles displayed progress at Monday and schedules the next local week boundary', () => {
    const sunday = new Date(2026, 6, 19, 23, 59, 30);
    const library = emptyPracticeLibrary(sunday);
    library.weeklyGoal = {
      week: '2026-07-13',
      targetMinutes: 180,
      completedMinutes: 75,
      targetSessions: 5,
      completedSessions: 3,
    };

    expect(millisecondsUntilNextPracticeWeek(sunday)).toBe(30_000);
    expect(reconcilePracticeLibraryWeek(library, sunday)).toBe(library);

    const monday = new Date(2026, 6, 20, 0, 0, 0);
    expect(reconcilePracticeLibraryWeek(library, monday).weeklyGoal).toEqual({
      week: '2026-07-20',
      targetMinutes: 180,
      completedMinutes: 0,
      targetSessions: 5,
      completedSessions: 0,
    });
    expect(millisecondsUntilNextPracticeWeek(monday)).toBe(7 * 24 * 60 * 60 * 1000);
  });

  it('claims each saved session once per owner and derives a minimum one-minute activity', () => {
    const claimed = new Set<string>();
    expect(claimSavedPracticeSessionMinutes(claimed, 'guest', { id: 'take-1', duration_seconds: 0 })).toBe(1);
    expect(claimSavedPracticeSessionMinutes(claimed, 'guest', { id: 'take-1', duration_seconds: 125 })).toBeNull();
    expect(claimSavedPracticeSessionMinutes(claimed, 'account:42', { id: 'take-1', duration_seconds: 125 })).toBe(2);
    expect(claimSavedPracticeSessionMinutes(claimed, 'account:42', { id: 'take-2', duration_seconds: Number.NaN })).toBe(1);
  });

  it('ships routable built-in packs for the focused workspace', () => {
    expect(BUILT_IN_PRACTICE_PACKS).toHaveLength(2);
    expect(BUILT_IN_PRACTICE_PACKS.every((pack) => pack.steps.length > 0 && pack.steps.every((step) => step.href.startsWith('/')))).toBe(true);
  });

  it('retries a quota failure with bounded optional history', () => {
    let calls = 0;
    let saved = '';
    const storage = { setItem: (_key: string, value: string) => { calls += 1; if (calls === 1) throw new Error('quota'); saved = value; } };
    const library = emptyPracticeLibrary();
    library.recents = Array.from({ length: 10 }, (_, index) => ({ kind: 'warmup', id: String(index), label: String(index), href: '/practice' }));
    library.reflections = Array.from({ length: 20 }, (_, index) => ({ id: String(index), text: 'note', createdAt: new Date().toISOString() }));
    expect(writePracticeLibrary(storage, 'guest', library)).toBe(true);
    expect(calls).toBe(2);
    expect(JSON.parse(saved).recents).toHaveLength(3);
    expect(JSON.parse(saved).reflections).toHaveLength(10);
  });

  it('removes only the deleted custom item and its matching shortcuts', () => {
    const library = emptyPracticeLibrary();
    library.customExercises = [{ id: 'custom-1', name: 'My scale', notes: ['C'], source: 'custom', createdAt: new Date().toISOString() }];
    library.metronomePresets = [{ id: 'preset-1', name: 'March', bpm: 96, numerator: 4, denominator: 4, subdivision: 'quarter', accentDownbeat: true, countIn: true }];
    library.favorites = [
      { kind: 'play-along', id: 'custom-1', label: 'My scale', href: '/practice/play-along?exercise=custom-1' },
      { kind: 'metronome', id: 'preset-1', label: 'March', href: '/metronome' },
    ];
    library.recents = [...library.favorites];

    const withoutExercise = removeCustomExercise(library, 'custom-1');
    expect(withoutExercise.customExercises).toEqual([]);
    expect(withoutExercise.favorites.map((item) => item.id)).toEqual(['preset-1']);
    const withoutPreset = removeMetronomePreset(withoutExercise, 'preset-1');
    expect(withoutPreset.metronomePresets).toEqual([]);
    expect(withoutPreset.favorites).toEqual([]);
    expect(withoutPreset.recents).toEqual([]);
  });

  it('updates a custom exercise in place while preserving creation data and shortcut references', () => {
    const library = emptyPracticeLibrary();
    library.customExercises = [{
      id: 'custom-1',
      name: 'Old slur',
      notes: ['C', 'G'],
      source: 'custom',
      createdAt: '2026-07-20T12:00:00.000Z',
    }];
    library.favorites = [{ kind: 'play-along', id: 'custom-1', label: 'Old slur', href: '/practice/play-along?exercise=custom-1' }];
    library.recents = [{ kind: 'play-along', id: 'custom-1', label: 'Old slur', href: '/practice/play-along?exercise=custom-1' }];

    const result = upsertCustomExercise(library, {
      id: 'custom-1',
      name: ' Lip slur focus ',
      notes: ['C', 'F', 'G'],
      source: 'custom',
    }, new Date('2026-07-23T12:00:00.000Z'));

    expect(result.item).toMatchObject({
      id: 'custom-1',
      name: 'Lip slur focus',
      notes: ['C', 'F', 'G'],
      createdAt: '2026-07-20T12:00:00.000Z',
    });
    expect(result.library.customExercises).toHaveLength(1);
    expect(result.library.favorites).toEqual([{ kind: 'play-along', id: 'custom-1', label: 'Lip slur focus', href: '/practice/play-along?exercise=custom-1' }]);
    expect(result.library.recents).toEqual([{ kind: 'play-along', id: 'custom-1', label: 'Lip slur focus', href: '/practice/play-along?exercise=custom-1' }]);
  });

  it('clears an account library, workspace, and best scores while preserving guest state', () => {
    const values = new Map<string, string>([
      [ownerPracticeKey('account:42'), 'account-library'],
      [ownerPracticeKey('guest'), 'guest-library'],
      ['brasstune.playalong.best.account%3A42.cmaj', '90'],
      ['brasstune.playalong.best.guest.cmaj', '80'],
      ['brasstune.practiceStreak.v2.account%3A42.days', '["2026-07-22"]'],
      ['brasstune.practiceStreak.v2.guest.days', '["2026-07-21"]'],
      ['brasstune.practice.days', '["2026-07-20"]'],
      ['brasstune.theme', 'brass-night'],
    ]);
    const local = {
      get length() { return values.size; },
      key: (index: number) => [...values.keys()][index] ?? null,
      removeItem: (key: string) => { values.delete(key); },
    };
    const removedSessionKeys: string[] = [];
    const removed = clearAccountPracticeState(local, { removeItem: (key: string) => removedSessionKeys.push(key) }, 'account:42');
    expect(removed).toBe(5);
    expect(values.has(ownerPracticeKey('account:42'))).toBe(false);
    expect(values.has('brasstune.playalong.best.account%3A42.cmaj')).toBe(false);
    expect(values.get(ownerPracticeKey('guest'))).toBe('guest-library');
    expect(values.get('brasstune.playalong.best.guest.cmaj')).toBe('80');
    expect(values.get('brasstune.practiceStreak.v2.guest.days')).toBe('["2026-07-21"]');
    expect(values.has('brasstune.practice.days')).toBe(false);
    expect(removedSessionKeys).toEqual([ownerWorkspaceKey('account:42')]);
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
