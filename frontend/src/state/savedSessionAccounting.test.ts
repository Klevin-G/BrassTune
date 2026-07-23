import { describe, expect, it } from 'vitest';
import { emptyPracticeLibrary, persistSavedPracticeSessionActivity } from '../domain/practiceLibrary';

describe('saved-session accounting persistence', () => {
  it('claims and counts a session only after storage succeeds, then rejects duplicate claims', () => {
    const claimed = new Set<string>();
    const writes: string[] = [];
    const storage = { setItem: (_key: string, value: string) => writes.push(value) };
    const library = emptyPracticeLibrary(new Date('2026-07-20T12:00:00Z'));
    const first = persistSavedPracticeSessionActivity({
      claimedSessionKeys: claimed, storage, ownerId: 'guest', library, session: { id: 'take-1', duration_seconds: 125 }, now: new Date('2026-07-20T12:00:00Z'),
    });

    expect(first).toMatchObject({ saved: true, minutes: 2 });
    expect(first.library.weeklyGoal).toMatchObject({ completedMinutes: 2, completedSessions: 1 });
    expect(writes).toHaveLength(1);
    expect(persistSavedPracticeSessionActivity({
      claimedSessionKeys: claimed, storage, ownerId: 'guest', library: first.library, session: { id: 'take-1', duration_seconds: 125 }, now: new Date('2026-07-20T12:00:00Z'),
    })).toMatchObject({ saved: false, minutes: null, failure: 'duplicate' });
  });

  it('does not claim on an unrecoverable storage failure, allowing the same saved session to retry', () => {
    const claimed = new Set<string>();
    const failingStorage = { setItem: () => { throw new Error('quota'); } };
    const library = emptyPracticeLibrary();
    const failed = persistSavedPracticeSessionActivity({
      claimedSessionKeys: claimed, storage: failingStorage, ownerId: 'guest', library, session: { id: 'retry-me', duration_seconds: 0 },
    });
    expect(failed).toMatchObject({ saved: false, minutes: null, library, failure: 'storage' });
    expect(claimed).toEqual(new Set());

    const saved = persistSavedPracticeSessionActivity({
      claimedSessionKeys: claimed, storage: { setItem: () => undefined }, ownerId: 'guest', library, session: { id: 'retry-me', duration_seconds: 0 },
    });
    expect(saved).toMatchObject({ saved: true, minutes: 1 });
  });
});
