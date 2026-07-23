import { clearPracticeStreakState } from './practiceStreak';

export const PRACTICE_LIBRARY_VERSION = 1 as const;
export const PRACTICE_PACK_VERSION = 1 as const;
export const PRACTICE_WORKSPACE_VERSION = 1 as const;
export const PRACTICE_AUDIO_PAUSE_EVENT = 'brasstune:pause-practice-audio';
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
  version: typeof PRACTICE_PACK_VERSION;
  id: string;
  name: string;
  description: string;
  steps: readonly PracticePackStep[];
}

export interface PracticeWorkspace {
  version: typeof PRACTICE_WORKSPACE_VERSION;
  pack: PracticePack;
  stepIndex: number;
  startedAt: string;
  elapsedSecondsByStep: Record<string, number>;
  completedStepIds: string[];
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

interface StoredPracticeWorkspace {
  version: typeof PRACTICE_WORKSPACE_VERSION;
  packId: string;
  packVersion: typeof PRACTICE_PACK_VERSION;
  stepIndex: number;
  startedAt: string;
  elapsedSecondsByStep: Record<string, number>;
  completedStepIds: string[];
}

const MAX_WORKSPACE_STEP_SECONDS = 24 * 60 * 60;

function exactObjectKeys(value: object, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  return actual.length === expected.length
    && actual.every((key, index) => key === [...expected].sort()[index]);
}

function executablePathMatchesKind(step: PracticePackStep): boolean {
  try {
    const url = new URL(step.href, 'https://brasstune.local');
    if (url.origin !== 'https://brasstune.local') return false;
    if (step.kind === 'warmup') return url.pathname === '/practice' && url.hash === '#warmup';
    if (step.kind === 'drone') return url.pathname === '/practice' && url.searchParams.get('tool') === 'drone';
    if (step.kind === 'play-along') return url.pathname === '/practice/scorer' && Boolean(url.searchParams.get('exercise'));
    if (step.kind === 'metronome') return url.pathname === '/metronome';
    if (step.kind === 'score') return url.pathname === '/practice/sheet-music';
    return false;
  } catch {
    return false;
  }
}

export function isExecutablePracticePack(pack: PracticePack): boolean {
  return pack.version === PRACTICE_PACK_VERSION
    && typeof pack.id === 'string'
    && pack.id.length > 0
    && pack.id.length <= 80
    && typeof pack.name === 'string'
    && pack.name.length > 0
    && typeof pack.description === 'string'
    && pack.steps.length >= 1
    && pack.steps.length <= 12
    && pack.steps.every((step) => (
      typeof step.id === 'string'
      && step.id.length > 0
      && step.id.length <= 80
      && typeof step.label === 'string'
      && step.label.length > 0
      && typeof step.instruction === 'string'
      && step.instruction.length > 0
      && executablePathMatchesKind(step)
    ))
    && new Set(pack.steps.map((step) => step.id)).size === pack.steps.length;
}

function packMatchesKnownDefinition(candidate: unknown, known: PracticePack, legacy = false): boolean {
  if (!candidate || typeof candidate !== 'object') return false;
  const value = candidate as Partial<PracticePack>;
  const expectedPackKeys = legacy
    ? ['description', 'id', 'name', 'steps']
    : ['description', 'id', 'name', 'steps', 'version'];
  if (!exactObjectKeys(value, expectedPackKeys)) return false;
  if (!legacy && value.version !== known.version) return false;
  if (
    value.id !== known.id
    || value.name !== known.name
    || value.description !== known.description
    || !Array.isArray(value.steps)
    || value.steps.length !== known.steps.length
  ) {
    return false;
  }
  return value.steps.every((candidateStep, index) => {
    if (!candidateStep || typeof candidateStep !== 'object') return false;
    if (!exactObjectKeys(candidateStep, ['href', 'id', 'instruction', 'kind', 'label'])) return false;
    const step = candidateStep as PracticePackStep;
    const knownStep = known.steps[index];
    let legacyHref = knownStep.href;
    if (legacy && known.id === 'daily-foundations' && knownStep.id === 'concert-bb') {
      legacyHref = '/practice?tool=drone&note=Bb';
    } else if (legacy && knownStep.kind === 'play-along') {
      legacyHref = `/practice/play-along?exercise=${knownStep.id}`;
    }
    return step.kind === knownStep.kind
      && step.id === knownStep.id
      && step.label === knownStep.label
      && step.href === legacyHref
      && step.instruction === knownStep.instruction;
  });
}

function canonicalPracticePack(candidate: unknown, legacy = false): PracticePack | null {
  if (!candidate || typeof candidate !== 'object') return null;
  const id = (candidate as { id?: unknown }).id;
  if (typeof id !== 'string') return null;
  const known = BUILT_IN_PRACTICE_PACKS.find((pack) => pack.id === id);
  return known && packMatchesKnownDefinition(candidate, known, legacy) ? known : null;
}

function emptyWorkspaceProgress(pack: PracticePack): Record<string, number> {
  return Object.fromEntries(pack.steps.map((step) => [step.id, 0]));
}

export function createPracticeWorkspace(pack: PracticePack, now = new Date()): PracticeWorkspace | null {
  const canonical = canonicalPracticePack(pack);
  if (!canonical || !Number.isFinite(now.getTime())) return null;
  return {
    version: PRACTICE_WORKSPACE_VERSION,
    pack: canonical,
    stepIndex: 0,
    startedAt: now.toISOString(),
    elapsedSecondsByStep: emptyWorkspaceProgress(canonical),
    completedStepIds: [],
  };
}

export function serializePracticeWorkspace(workspace: PracticeWorkspace): string | null {
  const canonical = canonicalPracticePack(workspace.pack);
  if (!canonical || workspace.version !== PRACTICE_WORKSPACE_VERSION) return null;
  const stored: StoredPracticeWorkspace = {
    version: PRACTICE_WORKSPACE_VERSION,
    packId: canonical.id,
    packVersion: canonical.version,
    stepIndex: workspace.stepIndex,
    startedAt: workspace.startedAt,
    elapsedSecondsByStep: workspace.elapsedSecondsByStep,
    completedStepIds: workspace.completedStepIds,
  };
  return hydrateStoredWorkspace(stored, canonical) ? JSON.stringify(stored) : null;
}

function hydrateStoredWorkspace(value: StoredPracticeWorkspace, pack: PracticePack): PracticeWorkspace | null {
  if (
    value.version !== PRACTICE_WORKSPACE_VERSION
    || value.packVersion !== pack.version
    || !Number.isInteger(value.stepIndex)
    || value.stepIndex < 0
    || value.stepIndex >= pack.steps.length
    || typeof value.startedAt !== 'string'
    || !Number.isFinite(Date.parse(value.startedAt))
    || !value.elapsedSecondsByStep
    || typeof value.elapsedSecondsByStep !== 'object'
    || Array.isArray(value.elapsedSecondsByStep)
    || !Array.isArray(value.completedStepIds)
  ) {
    return null;
  }
  const stepIds = pack.steps.map((step) => step.id);
  if (!exactObjectKeys(value.elapsedSecondsByStep, stepIds)) return null;
  const progress: Record<string, number> = {};
  for (const id of stepIds) {
    const seconds = value.elapsedSecondsByStep[id];
    if (!Number.isInteger(seconds) || seconds < 0 || seconds > MAX_WORKSPACE_STEP_SECONDS) return null;
    progress[id] = seconds;
  }
  if (
    new Set(value.completedStepIds).size !== value.completedStepIds.length
    || value.completedStepIds.some((id) => typeof id !== 'string' || !stepIds.includes(id))
  ) {
    return null;
  }
  return {
    version: PRACTICE_WORKSPACE_VERSION,
    pack,
    stepIndex: value.stepIndex,
    startedAt: value.startedAt,
    elapsedSecondsByStep: progress,
    completedStepIds: [...value.completedStepIds],
  };
}

export function parsePracticeWorkspace(raw: string | null): PracticeWorkspace | null {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw) as Partial<StoredPracticeWorkspace> & { pack?: unknown };
    if ('pack' in value) {
      // Migrate only the exact, previously shipped full-pack snapshot. Any
      // modified route, label, instruction, or extra field fails closed.
      const pack = canonicalPracticePack(value.pack, true);
      if (
        !pack
        || !exactObjectKeys(value, ['pack', 'startedAt', 'stepIndex'])
        || !Number.isInteger(value.stepIndex)
        || (value.stepIndex as number) < 0
        || (value.stepIndex as number) >= pack.steps.length
        || typeof value.startedAt !== 'string'
        || !Number.isFinite(Date.parse(value.startedAt))
      ) {
        return null;
      }
      return {
        version: PRACTICE_WORKSPACE_VERSION,
        pack,
        stepIndex: value.stepIndex as number,
        startedAt: value.startedAt,
        elapsedSecondsByStep: emptyWorkspaceProgress(pack),
        completedStepIds: pack.steps.slice(0, value.stepIndex as number).map((step) => step.id),
      };
    }
    if (!exactObjectKeys(value, [
      'completedStepIds',
      'elapsedSecondsByStep',
      'packId',
      'packVersion',
      'startedAt',
      'stepIndex',
      'version',
    ])) {
      return null;
    }
    const pack = typeof value.packId === 'string'
      ? BUILT_IN_PRACTICE_PACKS.find((item) => item.id === value.packId)
      : null;
    return pack ? hydrateStoredWorkspace(value as StoredPracticeWorkspace, pack) : null;
  } catch {
    return null;
  }
}

export function addPracticeWorkspaceElapsed(workspace: PracticeWorkspace, seconds = 1): PracticeWorkspace {
  if (!Number.isInteger(seconds) || seconds <= 0) return workspace;
  const step = workspace.pack.steps[workspace.stepIndex];
  const current = workspace.elapsedSecondsByStep[step.id] ?? 0;
  const elapsed = Math.min(MAX_WORKSPACE_STEP_SECONDS, current + seconds);
  if (elapsed === current) return workspace;
  return {
    ...workspace,
    elapsedSecondsByStep: { ...workspace.elapsedSecondsByStep, [step.id]: elapsed },
  };
}

export function completePracticeWorkspaceStep(workspace: PracticeWorkspace): PracticeWorkspace {
  const stepId = workspace.pack.steps[workspace.stepIndex].id;
  if (workspace.completedStepIds.includes(stepId)) return workspace;
  return { ...workspace, completedStepIds: [...workspace.completedStepIds, stepId] };
}

export function movePracticeWorkspace(workspace: PracticeWorkspace, stepIndex: number): PracticeWorkspace {
  if (!Number.isInteger(stepIndex) || stepIndex < 0 || stepIndex >= workspace.pack.steps.length || stepIndex === workspace.stepIndex) {
    return workspace;
  }
  const current = stepIndex > workspace.stepIndex ? completePracticeWorkspaceStep(workspace) : workspace;
  return { ...current, stepIndex };
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

function immutablePracticePack(pack: Omit<PracticePack, 'version'>): PracticePack {
  const steps = Object.freeze(pack.steps.map((step) => Object.freeze({ ...step })));
  return Object.freeze({ ...pack, version: PRACTICE_PACK_VERSION, steps });
}

export const BUILT_IN_PRACTICE_PACKS: readonly PracticePack[] = Object.freeze([
  immutablePracticePack({
    id: 'daily-foundations',
    name: 'Daily foundations',
    description: 'Warm up, center your sound, then finish with a steady scale.',
    steps: [
      { kind: 'warmup', id: 'guided-5', label: '5-minute warm-up', href: '/practice#warmup', instruction: 'Follow the five short warm-up steps.' },
      { kind: 'drone', id: 'concert-bb', label: 'Concert B♭ drone', href: '/practice?tool=drone&midi=70', instruction: 'Match the drone with an easy, relaxed sound.' },
      { kind: 'play-along', id: 'cmaj', label: 'C major scale', href: '/practice/scorer?exercise=cmaj', instruction: 'Hold every scale note for the full two seconds.' },
    ],
  }),
  immutablePracticePack({
    id: 'steady-time',
    name: 'Steady time',
    description: 'Set the pulse, then use it in a focused scale round.',
    steps: [
      { kind: 'metronome', id: 'steady-80', label: 'Metronome at 80', href: '/metronome?bpm=80', instruction: 'Listen for one bar, then join the beat.' },
      { kind: 'play-along', id: 'longtones', label: 'Long tones', href: '/practice/scorer?exercise=longtones', instruction: 'Keep each entrance clean and centered.' },
    ],
  }),
]);
