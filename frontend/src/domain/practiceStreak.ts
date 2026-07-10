// A forgiving, local-first practice streak + daily goal. Band students miss
// days, so a broken *daily* streak is demotivating — we keep a day streak but
// treat "today or yesterday" as alive, and also expose a simple minutes goal.
// Any activity counts (tuner time, a graded run, a saved take): call
// recordPracticeActivity() from those flows.

const DAYS_KEY = 'brasstune.practice.days'; // JSON: string[] of YYYY-MM-DD
const GOAL_KEY = 'brasstune.practice.goalMinutes';
const MINUTES_PREFIX = 'brasstune.practice.min.'; // + YYYY-MM-DD -> minutes

function todayKey(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

function readDays(): string[] {
  try {
    const raw = localStorage.getItem(DAYS_KEY);
    const parsed = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(parsed) ? (parsed.filter((d) => typeof d === 'string') as string[]) : [];
  } catch {
    return [];
  }
}

function writeDays(days: string[]): void {
  try {
    localStorage.setItem(DAYS_KEY, JSON.stringify(days.slice(-400)));
  } catch {
    /* storage full / disabled — streak is best-effort */
  }
}

/** Mark that the user practiced today (idempotent), optionally adding minutes. */
export function recordPracticeActivity(minutes = 0, now = new Date()): void {
  const key = todayKey(now);
  const days = readDays();
  if (!days.includes(key)) {
    days.push(key);
    writeDays(days);
  }
  if (minutes > 0) {
    try {
      const prev = Number(localStorage.getItem(MINUTES_PREFIX + key) ?? 0);
      localStorage.setItem(MINUTES_PREFIX + key, String(prev + minutes));
    } catch {
      /* best-effort */
    }
  }
}

function dayString(offset: number, from = new Date()): string {
  const d = new Date(from);
  d.setDate(d.getDate() - offset);
  return d.toISOString().slice(0, 10);
}

/** Current day streak. Alive if the user practiced today or yesterday. */
export function getDayStreak(now = new Date()): number {
  const days = new Set(readDays());
  let streak = 0;
  // Start from today if present, else yesterday (one-day grace).
  let offset = days.has(dayString(0, now)) ? 0 : days.has(dayString(1, now)) ? 1 : -1;
  if (offset === -1) return 0;
  while (days.has(dayString(offset, now))) {
    streak += 1;
    offset += 1;
  }
  return streak;
}

export function getGoalMinutes(): number {
  const raw = Number(localStorage.getItem(GOAL_KEY) ?? 0);
  return Number.isFinite(raw) && raw > 0 ? raw : 10; // default 10-minute goal
}

export function setGoalMinutes(minutes: number): void {
  try {
    localStorage.setItem(GOAL_KEY, String(Math.max(1, Math.round(minutes))));
  } catch {
    /* best-effort */
  }
}

export function getMinutesToday(now = new Date()): number {
  return Number(localStorage.getItem(MINUTES_PREFIX + todayKey(now)) ?? 0);
}

/** Practiced today at all? Used to pre-check onboarding checklist items. */
export function practicedToday(now = new Date()): boolean {
  return readDays().includes(todayKey(now));
}
