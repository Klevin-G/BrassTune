import { describe, expect, it } from 'vitest';
import {
  LEGACY_PRACTICE_DAYS_KEY,
  LEGACY_PRACTICE_GOAL_KEY,
  getDayStreak,
  getGoalMinutes,
  getMinutesToday,
  ownerPracticeStreakPrefix,
  recordPracticeActivity,
  setGoalMinutes,
} from './practiceStreak';

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    values,
    get length() { return values.size; },
    key: (index: number) => [...values.keys()][index] ?? null,
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
    removeItem: (key: string) => { values.delete(key); },
  };
}

describe('owner-scoped practice streaks', () => {
  it('keeps guest and account days, goals, and minutes isolated', () => {
    const storage = memoryStorage();
    const now = new Date('2026-07-22T12:00:00Z');
    recordPracticeActivity('guest', 4, now, storage);
    recordPracticeActivity('account:42', 9, now, storage);
    setGoalMinutes('guest', 12, storage);
    setGoalMinutes('account:42', 25, storage);

    expect(getMinutesToday('guest', now, storage)).toBe(4);
    expect(getMinutesToday('account:42', now, storage)).toBe(9);
    expect(getGoalMinutes('guest', storage)).toBe(12);
    expect(getGoalMinutes('account:42', storage)).toBe(25);
    expect(getDayStreak('guest', now, storage)).toBe(1);
    expect(getDayStreak('account:42', now, storage)).toBe(1);
    expect(ownerPracticeStreakPrefix('guest')).not.toBe(ownerPracticeStreakPrefix('account:42'));
  });

  it('migrates ambiguous legacy activity to guest only and removes global keys', () => {
    const storage = memoryStorage({
      [LEGACY_PRACTICE_DAYS_KEY]: '["2026-07-22"]',
      [LEGACY_PRACTICE_GOAL_KEY]: '17',
      'brasstune.practice.min.2026-07-22': '6',
    });
    const now = new Date('2026-07-22T12:00:00Z');

    expect(getDayStreak('account:42', now, storage)).toBe(0);
    expect(getDayStreak('guest', now, storage)).toBe(1);
    expect(getGoalMinutes('guest', storage)).toBe(17);
    expect(getMinutesToday('guest', now, storage)).toBe(6);
    expect(storage.values.has(LEGACY_PRACTICE_DAYS_KEY)).toBe(false);
    expect(storage.values.has(LEGACY_PRACTICE_GOAL_KEY)).toBe(false);
    expect(storage.values.has('brasstune.practice.min.2026-07-22')).toBe(false);
  });
});
