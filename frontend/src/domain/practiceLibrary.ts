import { clearPracticeStreakState } from './practiceStreak';

export const PRACTICE_LIBRARY_VERSION = 1 as const;
export const PRACTICE_LIBRARY_PREFIX = 'brasstune.practiceLibrary.v1.';
export const PRACTICE_WORKSPACE_PREFIX = 'brasstune.practiceWorkspace.v1.';
export const PLAY_ALONG_BEST_PREFIX = 'brasstune.playalong.best.';

export type PracticeTargetKind = 'warmup' | 'play-along' | 'metronome' | 'drone' | 'score';

export interface PracticeTarget {
  kind: PracticeTargetKind;
  id: string;
  label: string;
  href: string;
}

export interface CustomExercise {
  id: string;
  name: string;
  notes: string[];
  source: 'custom' | 'generated';
  createdAt: string;
}

export interface MetronomePreset {
  id: string;
  name: string;
  bpm: number;
  numerator: number;
  denominator: number;
  subdivision: 'quarter' | 'eighth' | 'triplet' | 'sixteenth';
  accentDownbeat: boolean;
  countIn: boolean;
}

export interface PracticeReflection {
  id: string;
  text: string;
  createdAt: string;
  sessionId?: string;
}

export interface WarmupProgress {
  elapsedSeconds: number;
  stepIndex: number;
  updatedAt: string;
}

export interface WeeklyGoal {
  week: string;
  targetMinutes: number;
  completedMinutes: number;
  targetSessions: number;
  completedSessions: number;
}

export interface PracticePackStep extends PracticeTarget {
  instruction: string;
}

export interface PracticePack {
  id: string;
  name: string;
  description: string;
  steps: PracticePackStep[];
}

export interface PracticeWorkspace {
  pack: PracticePack;
  stepIndex: number;
  startedAt: string;
}

export interface PracticeLibrary {
  version: typeof PRACTICE_LIBRARY_VERSION;
  customExercises: CustomExercise[];
  metronomePresets: MetronomePreset[];
  favorites: PracticeTarget[];
  recents: PracticeTarget[];
  reflections: PracticeReflection[];
  warmup: WarmupProgress;
  weeklyGoal: WeeklyGoal;
}

const LIMITS = {
  customExercises: 24,
  metronomePresets: 16,
  favorites: 16,
  recents: 10,
  reflections: 40,
} as const;

const NOTE_PATTERN = /^[A-Ga-g](?:#|b|♯|♭)?$/;

export function currentWeekKey(now = new Date()): string {
  const date = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const day = (date.getDay() + 6) % 7;
  date.setDate(date.getDate() - day);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function boundedInteger(value: unknown, minimum: number, maximum: number, fallback: number): number {
  return Math.max(minimum, Math.min(maximum, Math.round(finiteNumber(value, fallback))));
}

/**
 * Keeps weekly targets while resetting completion when a long-lived client
 * crosses into a new Monday-to-Sunday week. Call this at the point activity is
 * recorded as well as when persisted data is read: a provider can otherwise
 * keep an old week's library in memory indefinitely.
 */
export function reconcileWeeklyGoal(goal: Partial<WeeklyGoal> | undefined, now = new Date()): WeeklyGoal {
  const week = currentWeekKey(now);
  const targetMinutes = boundedInteger(goal?.targetMinutes, 5, 600, 60);
  const targetSessions = boundedInteger(goal?.targetSessions, 1, 21, 3);
  if (goal?.week !== week) {
    return { week, targetMinutes, completedMinutes: 0, targetSessions, completedSessions: 0 };
  }
  return {
    week,
    targetMinutes,
    completedMinutes: boundedInteger(goal.completedMinutes, 0, 10_000, 0),
    targetSessions,
    completedSessions: boundedInteger(goal.completedSessions, 0, 1_000, 0),
  };
}

export function recordPracticeActivity(library: PracticeLibrary, minutes: number, now = new Date()): PracticeLibrary {
  const weeklyGoal = reconcileWeeklyGoal(library.weeklyGoal, now);
  return {
    ...library,
    weeklyGoal: {
      ...weeklyGoal,
      completedMinutes: Math.min(10_000, weeklyGoal.completedMinutes + Math.max(1, Math.round(minutes) || 1)),
      completedSessions: Math.min(1_000, weeklyGoal.completedSessions + 1),
    },
  };
}

export interface SavedPracticeSessionActivity {
  id: string | number;
  duration_seconds?: number | null;
}

/**
 * Records saved-session progress only after the updated library has made it to
 * storage. That ordering leaves a failed save eligible for a later retry.
 */
export function persistSavedPracticeSessionActivity({
  claimedSessionKeys,
  storage,
  ownerId,
  library,
  session,
  now = new Date(),
}: {
  claimedSessionKeys: Set<string>;
  storage: Pick<Storage, 'setItem'>;
  ownerId: string;
  library: PracticeLibrary;
  session: SavedPracticeSessionActivity;
  now?: Date;
}): {
  saved: boolean;
  minutes: number | null;
  library: PracticeLibrary;
  failure: 'duplicate' | 'storage' | null;
} {
  const sessionKey = `${ownerId}:${String(session.id)}`;
  if (claimedSessionKeys.has(sessionKey)) {
    return { saved: false, minutes: null, library, failure: 'duplicate' };
  }
  const durationSeconds = typeof session.duration_seconds === 'number' && Number.isFinite(session.duration_seconds)
    ? Math.max(0, session.duration_seconds)
    : 0;
  const minutes = Math.max(1, Math.round(durationSeconds / 60));
  const next = recordPracticeActivity(library, minutes, now);
  if (!writePracticeLibrary(storage, ownerId, next)) {
    return { saved: false, minutes: null, library, failure: 'storage' };
  }
  claimedSessionKeys.add(sessionKey);
  return { saved: true, minutes, library: next, failure: null };
}

export function reconcilePracticeLibraryWeek(library: PracticeLibrary, now = new Date()): PracticeLibrary {
  const weeklyGoal = reconcileWeeklyGoal(library.weeklyGoal, now);
  if (
    weeklyGoal.week === library.weeklyGoal.week
    && weeklyGoal.targetMinutes === library.weeklyGoal.targetMinutes
    && weeklyGoal.completedMinutes === library.weeklyGoal.completedMinutes
    && weeklyGoal.targetSessions === library.weeklyGoal.targetSessions
    && weeklyGoal.completedSessions === library.weeklyGoal.completedSessions
  ) {
    return library;
  }
  return { ...library, weeklyGoal };
}

export function millisecondsUntilNextPracticeWeek(now = new Date()): number {
  const nextMonday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const mondayBasedDay = (nextMonday.getDay() + 6) % 7;
  nextMonday.setDate(nextMonday.getDate() + (7 - mondayBasedDay));
  nextMonday.setHours(0, 0, 0, 0);
  return Math.max(1, nextMonday.getTime() - now.getTime());
}

export function emptyPracticeLibrary(now = new Date()): PracticeLibrary {
  return {
    version: PRACTICE_LIBRARY_VERSION,
    customExercises: [],
    metronomePresets: [],
    favorites: [],
    recents: [],
    reflections: [],
    warmup: { elapsedSeconds: 0, stepIndex: 0, updatedAt: now.toISOString() },
    weeklyGoal: { week: currentWeekKey(now), targetMinutes: 60, completedMinutes: 0, targetSessions: 3, completedSessions: 0 },
  };
}

export function ownerPracticeKey(ownerId: string): string {
  return `${PRACTICE_LIBRARY_PREFIX}${encodeURIComponent(ownerId)}`;
}

export function ownerWorkspaceKey(ownerId: string): string {
  return `${PRACTICE_WORKSPACE_PREFIX}${encodeURIComponent(ownerId)}`;
}

export function ownerBestScorePrefix(ownerId: string): string {
  return `${PLAY_ALONG_BEST_PREFIX}${encodeURIComponent(ownerId)}.`;
}

export function clearAccountPracticeState(
  local: Pick<Storage, 'removeItem' | 'length' | 'key'>,
  session: Pick<Storage, 'removeItem'>,
  ownerId: string,
): number {
  if (!ownerId.startsWith('account:')) return 0;
  const keys = [ownerPracticeKey(ownerId)];
  const bestPrefix = ownerBestScorePrefix(ownerId);
  for (let index = 0; index < local.length; index += 1) {
    const key = local.key(index);
    if (key?.startsWith(bestPrefix)) keys.push(key);
  }
  keys.forEach((key) => local.removeItem(key));
  session.removeItem(ownerWorkspaceKey(ownerId));
  // Legacy streak keys were global and therefore unsafe to attribute. Account
  // deletion clears them along with this account's owner-scoped streak.
  const streakKeys = clearPracticeStreakState(local, ownerId, true);
  return keys.length + streakKeys + 1;
}

export function resolvePracticeOwner(auth: { loading: boolean; hasAuthSession: boolean; isSignedIn: boolean; profileId?: string | number | null }): string | null {
  if (auth.loading || (auth.hasAuthSession && auth.profileId == null)) return null;
  if (auth.isSignedIn && auth.profileId != null) return `account:${auth.profileId}`;
  return 'guest';
}

function finiteNumber(value: unknown, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : fallback;
}

function normalizeTarget(value: unknown): PracticeTarget | null {
  if (!value || typeof value !== 'object') return null;
  const target = value as Partial<PracticeTarget>;
  const valid = ['warmup', 'play-along', 'metronome', 'drone', 'score'].includes(target.kind ?? '')
    && typeof target.id === 'string'
    && typeof target.label === 'string'
    && typeof target.href === 'string'
    && target.href.startsWith('/');
  if (!valid) return null;
  return {
    kind: target.kind as PracticeTargetKind,
    id: target.id!.slice(0, 80),
    label: target.label!.trim().slice(0, 80),
    href: target.href!.slice(0, 240),
  };
}

export function normalizeNote(value: string): string | null {
  const note = value.trim().replace(/♯/g, '#').replace(/♭/g, 'b');
  if (!NOTE_PATTERN.test(note)) return null;
  return `${note[0].toUpperCase()}${note.slice(1)}`;
}

export function parseExerciseNotes(value: string): { notes: string[]; error: string | null } {
  const raw = value.split(/[\s,]+/).filter(Boolean);
  if (raw.length < 1 || raw.length > 32) {
    return { notes: [], error: 'Enter between 1 and 32 notes.' };
  }
  const notes = raw.map(normalizeNote);
  const badIndex = notes.findIndex((note) => !note);
  if (badIndex >= 0) {
    return { notes: [], error: `“${raw[badIndex]}” is not a note. Use names like C, F#, or Bb.` };
  }
  return { notes: notes as string[], error: null };
}

function normalizeExercise(value: unknown): CustomExercise | null {
  if (!value || typeof value !== 'object') return null;
  const item = value as Partial<CustomExercise>;
  const parsed = parseExerciseNotes(Array.isArray(item.notes) ? item.notes.join(' ') : '');
  if (!item.id || !item.name?.trim() || parsed.error) return null;
  return {
    id: item.id.slice(0, 80),
    name: item.name.trim().slice(0, 60),
    notes: parsed.notes,
    source: item.source === 'generated' ? 'generated' : 'custom',
    createdAt: typeof item.createdAt === 'string' ? item.createdAt : new Date(0).toISOString(),
  };
}

export function normalizeMetronomePreset(value: Partial<MetronomePreset>): MetronomePreset | null {
  const name = value.name?.trim().slice(0, 50);
  if (!value.id || !name) return null;
  const denominator = [2, 4, 8, 16].includes(Number(value.denominator)) ? Number(value.denominator) : 4;
  const subdivision = ['quarter', 'eighth', 'triplet', 'sixteenth'].includes(value.subdivision ?? '')
    ? value.subdivision as MetronomePreset['subdivision']
    : 'quarter';
  return {
    id: value.id.slice(0, 80),
    name,
    bpm: Math.max(20, Math.min(300, Math.round(finiteNumber(value.bpm, 96)))),
    numerator: Math.max(1, Math.min(16, Math.round(finiteNumber(value.numerator, 4)))),
    denominator,
    subdivision,
    accentDownbeat: value.accentDownbeat !== false,
    countIn: value.countIn !== false,
  };
}

export function parsePracticeLibrary(raw: string | null, now = new Date()): PracticeLibrary {
  const fallback = emptyPracticeLibrary(now);
  if (!raw) return fallback;
  try {
    const value = JSON.parse(raw) as Partial<PracticeLibrary>;
    if (!value || value.version !== PRACTICE_LIBRARY_VERSION) return fallback;
    const exercises = Array.isArray(value.customExercises) ? value.customExercises.map(normalizeExercise).filter(Boolean) as CustomExercise[] : [];
    const presets = Array.isArray(value.metronomePresets) ? value.metronomePresets.map((item) => normalizeMetronomePreset(item)).filter(Boolean) as MetronomePreset[] : [];
    const goalWeek = reconcileWeeklyGoal(value.weeklyGoal, now);
    return {
      version: PRACTICE_LIBRARY_VERSION,
      customExercises: exercises.slice(0, LIMITS.customExercises),
      metronomePresets: presets.slice(0, LIMITS.metronomePresets),
      favorites: (Array.isArray(value.favorites) ? value.favorites.map(normalizeTarget).filter(Boolean) as PracticeTarget[] : []).slice(0, LIMITS.favorites),
      recents: (Array.isArray(value.recents) ? value.recents.map(normalizeTarget).filter(Boolean) as PracticeTarget[] : []).slice(0, LIMITS.recents),
      reflections: (Array.isArray(value.reflections) ? value.reflections : []).filter((item): item is PracticeReflection => Boolean(item && typeof item.id === 'string' && typeof item.text === 'string' && typeof item.createdAt === 'string')).map((item) => ({ ...item, text: item.text.trim().slice(0, 280) })).filter((item) => item.text.length > 0).slice(0, LIMITS.reflections),
      warmup: {
        elapsedSeconds: Math.max(0, Math.min(300, Math.round(finiteNumber(value.warmup?.elapsedSeconds, 0)))),
        stepIndex: Math.max(0, Math.min(4, Math.round(finiteNumber(value.warmup?.stepIndex, 0)))),
        updatedAt: typeof value.warmup?.updatedAt === 'string' ? value.warmup.updatedAt : now.toISOString(),
      },
      weeklyGoal: {
        ...goalWeek,
      },
    };
  } catch {
    return fallback;
  }
}

export function readPracticeLibrary(storage: Pick<Storage, 'getItem'>, ownerId: string, now = new Date()): PracticeLibrary {
  try {
    return parsePracticeLibrary(storage.getItem(ownerPracticeKey(ownerId)), now);
  } catch {
    return emptyPracticeLibrary(now);
  }
}

export function writePracticeLibrary(storage: Pick<Storage, 'setItem'>, ownerId: string, library: PracticeLibrary): boolean {
  const key = ownerPracticeKey(ownerId);
  try {
    storage.setItem(key, JSON.stringify(library));
    return true;
  } catch {
    try {
      const compact = { ...library, recents: library.recents.slice(0, 3), reflections: library.reflections.slice(0, 10) };
      storage.setItem(key, JSON.stringify(compact));
      return true;
    } catch {
      return false;
    }
  }
}

export function upsertById<T extends { id: string }>(items: T[], item: T, limit: number): T[] {
  return [item, ...items.filter((existing) => existing.id !== item.id)].slice(0, limit);
}

export function upsertCustomExercise(
  library: PracticeLibrary,
  exercise: Omit<CustomExercise, 'createdAt'> & { createdAt?: string },
  now = new Date(),
): { library: PracticeLibrary; item: CustomExercise } {
  const existing = library.customExercises.find((item) => item.id === exercise.id);
  const item: CustomExercise = {
    id: exercise.id.slice(0, 80),
    name: exercise.name.trim().slice(0, 60),
    notes: exercise.notes.slice(0, 32),
    source: exercise.source,
    createdAt: existing?.createdAt ?? exercise.createdAt ?? now.toISOString(),
  };
  const updateTargetLabel = (target: PracticeTarget): PracticeTarget => (
    target.kind === 'play-along' && target.id === item.id
      ? { ...target, label: item.name }
      : target
  );
  return {
    item,
    library: {
      ...library,
      customExercises: upsertById(library.customExercises, item, LIMITS.customExercises),
      favorites: library.favorites.map(updateTargetLabel),
      recents: library.recents.map(updateTargetLabel),
    },
  };
}

export function removeCustomExercise(library: PracticeLibrary, id: string): PracticeLibrary {
  return {
    ...library,
    customExercises: library.customExercises.filter((item) => item.id !== id),
    favorites: library.favorites.filter((item) => !(item.kind === 'play-along' && item.id === id)),
    recents: library.recents.filter((item) => !(item.kind === 'play-along' && item.id === id)),
  };
}

export function removeMetronomePreset(library: PracticeLibrary, id: string): PracticeLibrary {
  return {
    ...library,
    metronomePresets: library.metronomePresets.filter((item) => item.id !== id),
    favorites: library.favorites.filter((item) => !(item.kind === 'metronome' && item.id === id)),
    recents: library.recents.filter((item) => !(item.kind === 'metronome' && item.id === id)),
  };
}

export const practiceLibraryLimits = LIMITS;

export const BUILT_IN_PRACTICE_PACKS: PracticePack[] = [
  {
    id: 'daily-foundations',
    name: 'Daily foundations',
    description: 'Warm up, center your sound, then finish with a steady scale.',
    steps: [
      { kind: 'warmup', id: 'guided-5', label: '5-minute warm-up', href: '/practice#warmup', instruction: 'Follow the five short warm-up steps.' },
      { kind: 'drone', id: 'concert-bb', label: 'Concert B♭ drone', href: '/practice?tool=drone&note=Bb', instruction: 'Match the drone with an easy, relaxed sound.' },
      { kind: 'play-along', id: 'cmaj', label: 'C major scale', href: '/practice/play-along?exercise=cmaj', instruction: 'Hold every scale note for the full two seconds.' },
    ],
  },
  {
    id: 'steady-time',
    name: 'Steady time',
    description: 'Set the pulse, then use it in a focused scale round.',
    steps: [
      { kind: 'metronome', id: 'steady-80', label: 'Metronome at 80', href: '/metronome?bpm=80', instruction: 'Listen for one bar, then join the beat.' },
      { kind: 'play-along', id: 'longtones', label: 'Long tones', href: '/practice/play-along?exercise=longtones', instruction: 'Keep each entrance clean and centered.' },
    ],
  },
];
