// A local-first practice streak. Every key is owner-scoped so guest and
// account activity can never contribute to one another's streak or goal.

export const PRACTICE_STREAK_PREFIX = 'brasstune.practiceStreak.v2.';
export const LEGACY_PRACTICE_DAYS_KEY = 'brasstune.practice.days';
export const LEGACY_PRACTICE_GOAL_KEY = 'brasstune.practice.goalMinutes';
export const LEGACY_PRACTICE_MINUTES_PREFIX = 'brasstune.practice.min.';

type StreakStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem' | 'length' | 'key'>;

export function ownerPracticeStreakPrefix(ownerId: string): string {
  return `${PRACTICE_STREAK_PREFIX}${encodeURIComponent(ownerId)}.`;
}

function ownerKeys(ownerId: string) {
  const prefix = ownerPracticeStreakPrefix(ownerId);
  return {
    days: `${prefix}days`,
    goal: `${prefix}goalMinutes`,
    minutes: `${prefix}min.`,
  };
}

function todayKey(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function legacyKeys(storage: Pick<Storage, 'length' | 'key'>): string[] {
  const keys: string[] = [];
  for (let index = 0; index < storage.length; index += 1) {
    const key = storage.key(index);
    if (key === LEGACY_PRACTICE_DAYS_KEY
      || key === LEGACY_PRACTICE_GOAL_KEY
      || key?.startsWith(LEGACY_PRACTICE_MINUTES_PREFIX)) keys.push(key);
  }
  return keys;
}

/**
 * Legacy values had no owner identity. Move them to guest only, which is the
 * least-privileged compatible owner, and remove the ambiguous global keys.
 */
export function migrateLegacyGuestPracticeStreak(storage: StreakStorage): number {
  const guest = ownerKeys('guest');
  const keys = legacyKeys(storage);
  try {
    const days = storage.getItem(LEGACY_PRACTICE_DAYS_KEY);
    const goal = storage.getItem(LEGACY_PRACTICE_GOAL_KEY);
    if (days != null && storage.getItem(guest.days) == null) storage.setItem(guest.days, days);
    if (goal != null && storage.getItem(guest.goal) == null) storage.setItem(guest.goal, goal);
    keys.filter((key) => key.startsWith(LEGACY_PRACTICE_MINUTES_PREFIX)).forEach((key) => {
      const value = storage.getItem(key);
      const date = key.slice(LEGACY_PRACTICE_MINUTES_PREFIX.length);
      if (value != null && storage.getItem(`${guest.minutes}${date}`) == null) storage.setItem(`${guest.minutes}${date}`, value);
    });
    keys.forEach((key) => storage.removeItem(key));
    return keys.length;
  } catch {
    return 0;
  }
}

export function clearPracticeStreakState(
  storage: Pick<Storage, 'removeItem' | 'length' | 'key'>,
  ownerId: string,
  clearLegacy = false,
): number {
  const prefix = ownerPracticeStreakPrefix(ownerId);
  const keys: string[] = [];
  for (let index = 0; index < storage.length; index += 1) {
    const key = storage.key(index);
    if (key?.startsWith(prefix)
      || (clearLegacy && (key === LEGACY_PRACTICE_DAYS_KEY
        || key === LEGACY_PRACTICE_GOAL_KEY
        || key?.startsWith(LEGACY_PRACTICE_MINUTES_PREFIX)))) keys.push(key);
  }
  keys.forEach((key) => storage.removeItem(key));
  return keys.length;
}

function prepareStorage(ownerId: string, storage: StreakStorage): ReturnType<typeof ownerKeys> {
  if (ownerId === 'guest') migrateLegacyGuestPracticeStreak(storage);
  return ownerKeys(ownerId);
}

function readDays(ownerId: string, storage: StreakStorage): string[] {
  try {
    const raw = storage.getItem(prepareStorage(ownerId, storage).days);
    const parsed = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(parsed) ? (parsed.filter((day) => typeof day === 'string') as string[]) : [];
  } catch {
    return [];
  }
}

function writeDays(ownerId: string, days: string[], storage: StreakStorage): void {
  try {
    storage.setItem(prepareStorage(ownerId, storage).days, JSON.stringify(days.slice(-400)));
  } catch {
    /* storage full / disabled — streak is best-effort */
  }
}

/** Mark that one owner practiced today (idempotent), optionally adding minutes. */
export function recordPracticeActivity(ownerId: string, minutes = 0, now = new Date(), storage: StreakStorage = localStorage): void {
  const key = todayKey(now);
  const days = readDays(ownerId, storage);
  if (!days.includes(key)) {
    days.push(key);
    writeDays(ownerId, days, storage);
  }
  if (minutes > 0) {
    try {
      const keys = prepareStorage(ownerId, storage);
      const prev = Number(storage.getItem(keys.minutes + key) ?? 0);
      storage.setItem(keys.minutes + key, String(prev + minutes));
    } catch {
      /* best-effort */
    }
  }
}

function dayString(offset: number, from = new Date()): string {
  const date = new Date(from);
  date.setDate(date.getDate() - offset);
  return date.toISOString().slice(0, 10);
}

/** Current day streak. Alive if this owner practiced today or yesterday. */
export function getDayStreak(ownerId: string, now = new Date(), storage: StreakStorage = localStorage): number {
  const days = new Set(readDays(ownerId, storage));
  let streak = 0;
  let offset = days.has(dayString(0, now)) ? 0 : days.has(dayString(1, now)) ? 1 : -1;
  if (offset === -1) return 0;
  while (days.has(dayString(offset, now))) {
    streak += 1;
    offset += 1;
  }
  return streak;
}

export function getGoalMinutes(ownerId: string, storage: StreakStorage = localStorage): number {
  const raw = Number(storage.getItem(prepareStorage(ownerId, storage).goal) ?? 0);
  return Number.isFinite(raw) && raw > 0 ? raw : 10;
}

export function setGoalMinutes(ownerId: string, minutes: number, storage: StreakStorage = localStorage): void {
  try {
    storage.setItem(prepareStorage(ownerId, storage).goal, String(Math.max(1, Math.round(minutes))));
  } catch {
    /* best-effort */
  }
}

export function getMinutesToday(ownerId: string, now = new Date(), storage: StreakStorage = localStorage): number {
  return Number(storage.getItem(prepareStorage(ownerId, storage).minutes + todayKey(now)) ?? 0);
}

export function practicedToday(ownerId: string, now = new Date(), storage: StreakStorage = localStorage): boolean {
  return readDays(ownerId, storage).includes(todayKey(now));
}
