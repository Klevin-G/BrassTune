import { describe, expect, it } from 'vitest';
import {
  PRACTICE_LIBRARY_VERSION,
  BUILT_IN_PRACTICE_PACKS,
  addPracticeWorkspaceElapsed,
  clearAccountPracticeState,
  completePracticeWorkspaceStep,
  completedPracticeWorkspaceMinutes,
  createPracticeWorkspace,
  currentWeekKey,
  detachPracticeReflectionsForSession,
  emptyPracticeLibrary,
  normalizeMetronomePreset,
  isExecutablePracticePack,
  isPracticeWorkspaceComplete,
  millisecondsUntilNextPracticeWeek,
  movePracticeWorkspace,
  ownerPracticeKey,
  ownerWorkspaceKey,
  parseExerciseNotes,
  parsePracticeLibrary,
  parsePracticeWorkspace,
  reconcilePracticeLibraryWeek,
  recordPracticeActivity,
  recordPracticeWorkspaceStepActivity,
  resolvePracticeOwner,
  removeCustomExercise,
  removeMetronomePreset,
  serializePracticeWorkspace,
  shouldRecordPracticeWorkspaceCompletion,
  upsertCustomExercise,
  writePracticeLibrary,
} from './practiceLibrary';

describe('practice library storage', () => {
  it('isolates guest and account keys and keeps an unresolved account out of guest storage', () => {
    expect(ownerPracticeKey('guest')).not.toBe(ownerPracticeKey('account:42'));
    expect(resolvePracticeOwner({ loading: true, hasAuthSession: false, isSignedIn: false })).toBeNull();
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: true, isSignedIn: false })).toBeNull();
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: true, isSignedIn: false, localPracticeOwnerId: 'account:42' })).toBe('account:42');
    expect(resolvePracticeOwner({ loading: false, hasAuthSession: true, isSignedIn: false, localPracticeOwnerId: 'account:../guest' })).toBeNull();
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

  it('ships routable built-in packs for the focused workspace', () => {
    expect(BUILT_IN_PRACTICE_PACKS).toHaveLength(2);
    expect(BUILT_IN_PRACTICE_PACKS.every((pack) => pack.steps.length >= 1 && pack.steps.length <= 12 && isExecutablePracticePack(pack))).toBe(true);
    expect(BUILT_IN_PRACTICE_PACKS.every((pack) => Object.isFrozen(pack) && Object.isFrozen(pack.steps) && pack.steps.every(Object.isFrozen))).toBe(true);
  });

  it('persists only a canonical pack reference with active-block progress and completion', () => {
    const pack = BUILT_IN_PRACTICE_PACKS[0];
    const created = createPracticeWorkspace(pack, new Date('2026-07-23T12:00:00.000Z'));
    expect(created).not.toBeNull();
    let workspace = addPracticeWorkspaceElapsed(created!, 17);
    workspace = movePracticeWorkspace(workspace, 1);
    workspace = addPracticeWorkspaceElapsed(workspace, 8);
    workspace = completePracticeWorkspaceStep(workspace);

    const serialized = serializePracticeWorkspace(workspace);
    expect(serialized).not.toBeNull();
    const stored = JSON.parse(serialized!);
    expect(stored).toMatchObject({
      version: 1,
      packId: 'daily-foundations',
      packVersion: 1,
      stepIndex: 1,
      elapsedSecondsByStep: { 'guided-5': 17, 'concert-bb': 8, cmaj: 0 },
      completedStepIds: ['guided-5', 'concert-bb'],
      activityRecordedStepIds: [],
    });
    expect(stored).not.toHaveProperty('pack');
    expect(parsePracticeWorkspace(serialized)).toEqual(workspace);
  });

  it('recognizes pack completion and derives one bounded goal activity duration', () => {
    let workspace = createPracticeWorkspace(BUILT_IN_PRACTICE_PACKS[0])!;
    workspace = addPracticeWorkspaceElapsed(workspace, 31);
    workspace = movePracticeWorkspace(workspace, 1);
    workspace = addPracticeWorkspaceElapsed(workspace, 30);
    workspace = movePracticeWorkspace(workspace, 2);
    expect(isPracticeWorkspaceComplete(workspace)).toBe(false);
    workspace = completePracticeWorkspaceStep(workspace);
    expect(isPracticeWorkspaceComplete(workspace)).toBe(true);
    expect(shouldRecordPracticeWorkspaceCompletion(workspace)).toBe(true);
    expect(completedPracticeWorkspaceMinutes(workspace)).toBe(1);
    expect(completePracticeWorkspaceStep(workspace)).toBe(workspace);
  });

  it('attributes real warm-up and Play-Along activity once so pack completion cannot double-count it', () => {
    let workspace = createPracticeWorkspace(BUILT_IN_PRACTICE_PACKS[0])!;
    const unrelated = recordPracticeWorkspaceStepActivity(workspace, { kind: 'play-along', id: 'longtones' });
    expect(unrelated).toBe(workspace);

    workspace = recordPracticeWorkspaceStepActivity(workspace, { kind: 'warmup', id: 'guided-5' });
    expect(workspace.activityRecordedStepIds).toEqual(['guided-5']);
    expect(recordPracticeWorkspaceStepActivity(workspace, { kind: 'warmup', id: 'guided-5' })).toBe(workspace);

    workspace = recordPracticeWorkspaceStepActivity(workspace, { kind: 'play-along', id: 'cmaj' });
    workspace = movePracticeWorkspace(workspace, 1);
    workspace = movePracticeWorkspace(workspace, 2);
    workspace = completePracticeWorkspaceStep(workspace);
    expect(workspace.activityRecordedStepIds).toEqual(['guided-5', 'cmaj']);
    expect(isPracticeWorkspaceComplete(workspace)).toBe(true);
    expect(shouldRecordPracticeWorkspaceCompletion(workspace)).toBe(false);
  });

  it('detaches only reflections for a deleted session while preserving their text', () => {
    const library = emptyPracticeLibrary();
    library.reflections = [
      { id: 'session-note', text: 'Keep the attack light.', createdAt: '2026-07-23T12:00:00Z', sessionId: '-42' },
      { id: 'other-note', text: 'Use more air.', createdAt: '2026-07-23T12:01:00Z', sessionId: '-43' },
      { id: 'general-note', text: 'Practice slowly.', createdAt: '2026-07-23T12:02:00Z' },
    ];
    const detached = detachPracticeReflectionsForSession(library, '-42');
    expect(detached.reflections).toEqual([
      { id: 'session-note', text: 'Keep the attack light.', createdAt: '2026-07-23T12:00:00Z' },
      library.reflections[1],
      library.reflections[2],
    ]);
    expect(detachPracticeReflectionsForSession(detached, '-42')).toBe(detached);
  });

  it('migrates only the exact legacy pack snapshot and rejects altered workspace storage', () => {
    const pack = BUILT_IN_PRACTICE_PACKS[0];
    const legacyPack = JSON.parse(JSON.stringify(pack));
    delete legacyPack.version;
    legacyPack.steps[1].href = '/practice?tool=drone&note=Bb';
    legacyPack.steps[2].href = '/practice/play-along?exercise=cmaj';
    const legacy = JSON.stringify({
      pack: legacyPack,
      stepIndex: 1,
      startedAt: '2026-07-23T12:00:00.000Z',
    });
    expect(parsePracticeWorkspace(legacy)).toMatchObject({
      pack,
      stepIndex: 1,
      completedStepIds: ['guided-5'],
    });

    const tamperedPack = JSON.parse(legacy);
    tamperedPack.pack.steps[1].href = 'https://example.test/capture';
    expect(parsePracticeWorkspace(JSON.stringify(tamperedPack))).toBeNull();

    const stored = JSON.parse(serializePracticeWorkspace(createPracticeWorkspace(pack)!)!);
    const legacyStored = { ...stored };
    delete legacyStored.activityRecordedStepIds;
    expect(parsePracticeWorkspace(JSON.stringify(legacyStored))).toMatchObject({
      activityRecordedStepIds: [],
    });
    expect(parsePracticeWorkspace(JSON.stringify({ ...stored, stepIndex: 99 }))).toBeNull();
    expect(parsePracticeWorkspace(JSON.stringify({ ...stored, packVersion: 99 }))).toBeNull();
    expect(parsePracticeWorkspace(JSON.stringify({ ...stored, injectedRoute: '/admin' }))).toBeNull();
    expect(parsePracticeWorkspace(JSON.stringify({
      ...stored,
      elapsedSecondsByStep: { ...stored.elapsedSecondsByStep, 'concert-bb': -1 },
    }))).toBeNull();
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
