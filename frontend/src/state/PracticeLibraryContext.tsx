import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import {
  PRACTICE_LIBRARY_VERSION,
  addPracticeWorkspaceElapsed,
  completePracticeWorkspaceStep,
  completedPracticeWorkspaceMinutes,
  createPracticeWorkspace,
  emptyPracticeLibrary,
  detachPracticeReflectionsForSession,
  isPracticeWorkspaceComplete,
  movePracticeWorkspace,
  normalizeMetronomePreset,
  ownerWorkspaceKey,
  parsePracticeWorkspace,
  persistSavedPracticeSessionActivity,
  practiceLibraryLimits,
  readPracticeLibrary,
  reconcilePracticeLibraryWeek,
  recordPracticeActivity,
  millisecondsUntilNextPracticeWeek,
  removeCustomExercise,
  removeMetronomePreset,
  resolvePracticeOwner,
  serializePracticeWorkspace,
  upsertById,
  upsertCustomExercise,
  writePracticeLibrary,
  type CustomExercise,
  type MetronomePreset,
  type PracticeLibrary,
  type PracticePack,
  type PracticeReflection,
  type PracticeTarget,
  type PracticeWorkspace,
  type WarmupProgress,
  type SavedPracticeSessionActivity,
} from '../domain/practiceLibrary';
import { recordPracticeActivity as recordPracticeStreakActivity } from '../domain/practiceStreak';
import { useI18n } from '../i18n/LocaleContext';
import { useAuth } from './AuthContext';

interface PracticeLibraryState {
  ownerId: string | null;
  library: PracticeLibrary;
  workspace: PracticeWorkspace | null;
  storageError: string | null;
  saveExercise: (exercise: Omit<CustomExercise, 'id' | 'createdAt'> & { id?: string }) => CustomExercise;
  deleteExercise: (id: string) => void;
  saveMetronomePreset: (preset: Omit<MetronomePreset, 'id'> & { id?: string }) => MetronomePreset | null;
  deleteMetronomePreset: (id: string) => void;
  toggleFavorite: (target: PracticeTarget) => void;
  isFavorite: (target: PracticeTarget) => boolean;
  recordRecent: (target: PracticeTarget) => void;
  setWeeklyGoal: (minutes: number, sessions?: number) => void;
  recordActivity: (minutes: number) => void;
  recordSavedSession: (session: SavedPracticeSessionActivity) => boolean;
  saveReflection: (text: string, sessionId?: string) => PracticeReflection | null;
  updateReflection: (id: string, text: string) => boolean;
  deleteReflection: (id: string) => void;
  detachReflectionsForSession: (sessionId: string) => void;
  setWarmupProgress: (progress: Pick<WarmupProgress, 'elapsedSeconds' | 'stepIndex'>) => void;
  startWorkspace: (pack: PracticePack) => void;
  moveWorkspace: (stepIndex: number) => void;
  addWorkspaceElapsed: (seconds?: number) => void;
  completeWorkspaceStep: () => void;
  exitWorkspace: () => void;
}

const PracticeLibraryContext = createContext<PracticeLibraryState | null>(null);

interface LoadedPracticeState {
  ownerId: string | null;
  library: PracticeLibrary;
  workspace: PracticeWorkspace | null;
  storageError: string | null;
}

export function practiceLibraryGateState({
  loading,
  hasAuthSession,
  hasProfile,
  hasLocalPracticeOwner = false,
  ownerReady,
}: {
  loading: boolean;
  hasAuthSession: boolean;
  hasProfile: boolean;
  hasLocalPracticeOwner?: boolean;
  ownerReady: boolean;
}): 'loading' | 'recovery' | 'ready' {
  if (loading) return 'loading';
  if (hasAuthSession && !hasProfile && !hasLocalPracticeOwner) return 'recovery';
  if (!ownerReady) return 'loading';
  return 'ready';
}

function createId(prefix: string): string {
  const suffix = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  return `${prefix}-${suffix}`;
}

function readWorkspace(ownerId: string): PracticeWorkspace | null {
  try {
    const raw = sessionStorage.getItem(ownerWorkspaceKey(ownerId));
    const workspace = parsePracticeWorkspace(raw);
    if (raw && !workspace) sessionStorage.removeItem(ownerWorkspaceKey(ownerId));
    return workspace;
  } catch {
    return null;
  }
}

function UnresolvedIdentityRecovery({
  retry,
  signOut,
  continueAsGuest,
  onGuestTransitionState,
}: {
  retry: () => Promise<void>;
  signOut: () => Promise<void>;
  continueAsGuest: () => Promise<void>;
  onGuestTransitionState: (state: 'idle' | 'pending' | 'failed') => void;
}) {
  const { t } = useI18n();
  const [busyAction, setBusyAction] = useState<'retry' | 'sign-out' | 'guest' | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const guestTransition = useRef(continueAsGuest);

  const retryProfile = async () => {
    if (busyAction) return;
    setBusyAction('retry');
    setActionError(null);
    try {
      await retry();
    } finally {
      setBusyAction(null);
    }
  };

  const leaveAccount = async () => {
    if (busyAction) return;
    setBusyAction('sign-out');
    setActionError(null);
    try {
      await signOut();
      onGuestTransitionState('idle');
    } catch {
      setActionError(t('settings.signOutFailed'));
    } finally {
      setBusyAction(null);
    }
  };

  const enterGuest = async () => {
    if (busyAction) return;
    setBusyAction('guest');
    setActionError(null);
    onGuestTransitionState('pending');
    try {
      await guestTransition.current();
      onGuestTransitionState('idle');
    } catch {
      setActionError(t('settings.signOutFailed'));
      onGuestTransitionState('failed');
    } finally {
      setBusyAction(null);
    }
  };

  return (
    <main className="content" id="main-content" tabIndex={-1}>
      <section className="section-card" aria-labelledby="identity-recovery-title" aria-busy={busyAction != null}>
        <p className="eyebrow">BrassTune</p>
        <h1 id="identity-recovery-title">{t('auth.profileRecoveryTitle')}</h1>
        <p>{t('auth.profileRecoveryBody')}</p>
        <div className="alert" role="status">{t('error.authUnavailable')}</div>
        {actionError && <div className="alert" role="alert">{actionError}</div>}
        <div className="button-row">
          <button className="primary-button" type="button" disabled={busyAction != null} onClick={() => void retryProfile()}>
            {busyAction === 'retry' ? t('auth.restore') : t('auth.tryAgain')}
          </button>
          <button className="ghost-button" type="button" disabled={busyAction != null} onClick={() => void leaveAccount()}>
            {t('settings.signOut')}
          </button>
          <button className="ghost-button" type="button" disabled={busyAction != null} onClick={() => void enterGuest()}>
            {t('auth.continueGuest')}
          </button>
        </div>
      </section>
    </main>
  );
}

const systemPracticeClock = () => new Date();

export function PracticeLibraryProvider({
  children,
  now = systemPracticeClock,
}: {
  children: ReactNode;
  now?: () => Date;
}) {
  const auth = useAuth();
  const { t } = useI18n();
  const ownerId = resolvePracticeOwner({
    loading: auth.loading,
    hasAuthSession: auth.hasAuthSession,
    isSignedIn: auth.isSignedIn,
    profileId: auth.profile?.id,
    localPracticeOwnerId: auth.localPracticeOwnerId,
  });
  const [loadedState, setLoadedState] = useState<LoadedPracticeState>(() => ({
    ownerId,
    library: ownerId ? readPracticeLibrary(localStorage, ownerId, now()) : emptyPracticeLibrary(now()),
    workspace: ownerId ? readWorkspace(ownerId) : null,
    storageError: null,
  }));
  const [guestRecoveryState, setGuestRecoveryState] = useState<'idle' | 'pending' | 'failed'>('idle');
  const claimedSavedSessionKeysRef = useRef(new Set<string>());
  const loadedStateRef = useRef(loadedState);
  loadedStateRef.current = loadedState;
  const ownerReady = ownerId != null && loadedState.ownerId === ownerId;
  const library = loadedState.library;
  const workspace = loadedState.workspace;
  const storageError = loadedState.storageError;

  useEffect(() => {
    const next = {
      ownerId,
      library: ownerId ? readPracticeLibrary(localStorage, ownerId, now()) : emptyPracticeLibrary(now()),
      workspace: ownerId ? readWorkspace(ownerId) : null,
      storageError: null,
    };
    loadedStateRef.current = next;
    setLoadedState(next);
  }, [now, ownerId]);

  const updateLibrary = useCallback((update: (current: PracticeLibrary) => PracticeLibrary) => {
    const current = loadedStateRef.current;
    if (!ownerId || current.ownerId !== ownerId) return false;
    const nextLibrary = update(current.library);
    if (nextLibrary === current.library) return true;
    const next = writePracticeLibrary(localStorage, ownerId, nextLibrary)
      ? { ...current, library: nextLibrary, storageError: null }
      : { ...current, storageError: 'This device is out of browser storage. Your latest practice-library change could not be saved.' };
    loadedStateRef.current = next;
    setLoadedState(next);
    return next.storageError == null;
  }, [ownerId]);

  const reconcileDisplayedWeek = useCallback(() => {
    const currentDate = now();
    const current = loadedStateRef.current;
    if (!ownerId || current.ownerId !== ownerId) return;
    const nextLibrary = reconcilePracticeLibraryWeek(current.library, currentDate);
    if (nextLibrary === current.library) return;
    const next = writePracticeLibrary(localStorage, ownerId, nextLibrary)
      ? { ...current, library: nextLibrary, storageError: null }
      : { ...current, storageError: 'This device is out of browser storage. Your weekly practice progress could not be updated.' };
    loadedStateRef.current = next;
    setLoadedState(next);
  }, [now, ownerId]);

  useEffect(() => {
    if (!ownerId || !ownerReady) return undefined;
    let rolloverTimer: number | undefined;
    const scheduleRollover = () => {
      if (rolloverTimer != null) window.clearTimeout(rolloverTimer);
      rolloverTimer = window.setTimeout(() => {
        reconcileDisplayedWeek();
        scheduleRollover();
      }, millisecondsUntilNextPracticeWeek(now()));
    };
    const reconcileAndReschedule = () => {
      reconcileDisplayedWeek();
      scheduleRollover();
    };
    const handleVisibility = () => {
      if (!document.hidden) reconcileAndReschedule();
    };

    scheduleRollover();
    window.addEventListener('focus', reconcileAndReschedule);
    document.addEventListener('visibilitychange', handleVisibility);
    return () => {
      if (rolloverTimer != null) window.clearTimeout(rolloverTimer);
      window.removeEventListener('focus', reconcileAndReschedule);
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [now, ownerId, ownerReady, reconcileDisplayedWeek]);

  const saveExercise = useCallback((exercise: Omit<CustomExercise, 'id' | 'createdAt'> & { id?: string }) => {
    const draft = {
      id: exercise.id ?? createId('exercise'),
      name: exercise.name.trim().slice(0, 60),
      notes: exercise.notes.slice(0, 32),
      source: exercise.source,
      createdAt: new Date().toISOString(),
    };
    const item = upsertCustomExercise(library, draft).item;
    updateLibrary((current) => upsertCustomExercise(current, draft).library);
    return item;
  }, [library, updateLibrary]);

  const deleteExercise = useCallback((id: string) => {
    updateLibrary((current) => removeCustomExercise(current, id));
  }, [updateLibrary]);

  const saveMetronomePreset = useCallback((preset: Omit<MetronomePreset, 'id'> & { id?: string }) => {
    const item = normalizeMetronomePreset({ ...preset, id: preset.id ?? createId('preset') });
    if (!item) return null;
    updateLibrary((current) => ({ ...current, metronomePresets: upsertById(current.metronomePresets, item, practiceLibraryLimits.metronomePresets) }));
    return item;
  }, [updateLibrary]);

  const deleteMetronomePreset = useCallback((id: string) => {
    updateLibrary((current) => removeMetronomePreset(current, id));
  }, [updateLibrary]);

  const targetKey = (target: PracticeTarget) => `${target.kind}:${target.id}`;

  const isFavorite = useCallback((target: PracticeTarget) => {
    const key = targetKey(target);
    return library.favorites.some((item) => targetKey(item) === key);
  }, [library.favorites]);

  const toggleFavorite = useCallback((target: PracticeTarget) => {
    updateLibrary((current) => {
      const key = targetKey(target);
      const exists = current.favorites.some((item) => targetKey(item) === key);
      return {
        ...current,
        favorites: exists
          ? current.favorites.filter((item) => targetKey(item) !== key)
          : [target, ...current.favorites].slice(0, practiceLibraryLimits.favorites),
      };
    });
  }, [updateLibrary]);

  const recordRecent = useCallback((target: PracticeTarget) => {
    updateLibrary((current) => {
      const key = targetKey(target);
      return { ...current, recents: [target, ...current.recents.filter((item) => targetKey(item) !== key)].slice(0, practiceLibraryLimits.recents) };
    });
  }, [updateLibrary]);

  const setWeeklyGoal = useCallback((minutes: number, sessions?: number) => {
    updateLibrary((current) => ({
      ...current,
      weeklyGoal: {
        ...current.weeklyGoal,
        targetMinutes: Math.max(5, Math.min(600, Math.round(minutes) || 5)),
        targetSessions: Math.max(1, Math.min(21, Math.round(sessions ?? current.weeklyGoal.targetSessions) || 1)),
      },
    }));
  }, [updateLibrary]);

  const recordActivity = useCallback((minutes: number) => {
    updateLibrary((current) => recordPracticeActivity(current, minutes, now()));
  }, [now, updateLibrary]);

  const recordSavedSession = useCallback((session: SavedPracticeSessionActivity) => {
    if (!ownerId) return false;
    const current = loadedStateRef.current;
    if (current.ownerId !== ownerId) return false;
    const result = persistSavedPracticeSessionActivity({
      claimedSessionKeys: claimedSavedSessionKeysRef.current,
      storage: localStorage,
      ownerId,
      library: current.library,
      session,
      now: now(),
    });
    if (!result.saved || result.minutes == null) {
      if (result.failure === 'storage') {
        const next = {
          ...current,
          storageError: 'This device is out of browser storage. Your saved practice could not be added to weekly progress.',
        };
        loadedStateRef.current = next;
        setLoadedState(next);
      }
      return false;
    }
    const next = { ...current, library: result.library, storageError: null };
    loadedStateRef.current = next;
    setLoadedState(next);
    recordPracticeStreakActivity(ownerId, result.minutes);
    return true;
  }, [now, ownerId]);

  const saveReflection = useCallback((text: string, sessionId?: string) => {
    const trimmed = text.trim().slice(0, 280);
    if (!trimmed) return null;
    const reflection: PracticeReflection = { id: createId('reflection'), text: trimmed, createdAt: new Date().toISOString(), sessionId };
    updateLibrary((current) => ({ ...current, reflections: [reflection, ...current.reflections].slice(0, practiceLibraryLimits.reflections) }));
    return reflection;
  }, [updateLibrary]);

  const updateReflection = useCallback((id: string, text: string) => {
    const trimmed = text.trim().slice(0, 280);
    if (!trimmed) return false;
    updateLibrary((current) => ({
      ...current,
      reflections: current.reflections.map((item) => item.id === id ? { ...item, text: trimmed } : item),
    }));
    return true;
  }, [updateLibrary]);

  const deleteReflection = useCallback((id: string) => {
    updateLibrary((current) => ({ ...current, reflections: current.reflections.filter((item) => item.id !== id) }));
  }, [updateLibrary]);

  const detachReflectionsForSession = useCallback((sessionId: string) => {
    updateLibrary((current) => detachPracticeReflectionsForSession(current, sessionId));
  }, [updateLibrary]);

  const setWarmupProgress = useCallback((progress: Pick<WarmupProgress, 'elapsedSeconds' | 'stepIndex'>) => {
    const elapsedSeconds = Math.max(0, Math.min(300, Math.round(progress.elapsedSeconds)));
    const stepIndex = Math.max(0, Math.min(4, Math.round(progress.stepIndex)));
    updateLibrary((current) => {
      if (current.warmup.elapsedSeconds === elapsedSeconds && current.warmup.stepIndex === stepIndex) return current;
      return {
        ...current,
        warmup: {
          elapsedSeconds,
          stepIndex,
          updatedAt: new Date().toISOString(),
        },
      };
    });
  }, [updateLibrary]);

  const persistWorkspace = useCallback((next: PracticeWorkspace | null) => {
    const current = loadedStateRef.current;
    if (!ownerId || current.ownerId !== ownerId) return;
    let updated: LoadedPracticeState;
    try {
      const serialized = next ? serializePracticeWorkspace(next) : null;
      if (next && !serialized) {
        sessionStorage.removeItem(ownerWorkspaceKey(ownerId));
        updated = {
          ...current,
          workspace: null,
          storageError: 'This practice pack could not be verified, so focused mode was closed.',
        };
      } else {
        if (serialized) sessionStorage.setItem(ownerWorkspaceKey(ownerId), serialized);
        else sessionStorage.removeItem(ownerWorkspaceKey(ownerId));
        updated = { ...current, workspace: next, storageError: null };
      }
    } catch {
      updated = {
        ...current,
        workspace: next,
        storageError: 'Focused mode will work for this page, but this browser could not remember it between pages.',
      };
    }
    loadedStateRef.current = updated;
    setLoadedState(updated);
  }, [ownerId]);

  const startWorkspace = useCallback((pack: PracticePack) => {
    persistWorkspace(createPracticeWorkspace(pack));
  }, [persistWorkspace]);

  const moveWorkspace = useCallback((stepIndex: number) => {
    const current = loadedStateRef.current.workspace;
    if (!current) return;
    persistWorkspace(movePracticeWorkspace(current, stepIndex));
  }, [persistWorkspace]);

  const addWorkspaceElapsed = useCallback((seconds = 1) => {
    const current = loadedStateRef.current.workspace;
    if (!current || isPracticeWorkspaceComplete(current)) return;
    persistWorkspace(addPracticeWorkspaceElapsed(current, seconds));
  }, [persistWorkspace]);

  const completeWorkspaceStep = useCallback(() => {
    const current = loadedStateRef.current.workspace;
    if (!current) return;
    const wasComplete = isPracticeWorkspaceComplete(current);
    const next = completePracticeWorkspaceStep(current);
    persistWorkspace(next);
    if (!wasComplete && isPracticeWorkspaceComplete(next)) {
      recordActivity(completedPracticeWorkspaceMinutes(next));
    }
  }, [persistWorkspace, recordActivity]);

  const exitWorkspace = useCallback(() => persistWorkspace(null), [persistWorkspace]);

  const value = useMemo<PracticeLibraryState>(() => ({
    ownerId,
    library: { ...library, version: PRACTICE_LIBRARY_VERSION },
    workspace,
    storageError,
    saveExercise,
    deleteExercise,
    saveMetronomePreset,
    deleteMetronomePreset,
    toggleFavorite,
    isFavorite,
    recordRecent,
    setWeeklyGoal,
    recordActivity,
    recordSavedSession,
    saveReflection,
    updateReflection,
    deleteReflection,
    detachReflectionsForSession,
    setWarmupProgress,
    startWorkspace,
    moveWorkspace,
    addWorkspaceElapsed,
    completeWorkspaceStep,
    exitWorkspace,
  }), [addWorkspaceElapsed, completeWorkspaceStep, deleteExercise, deleteMetronomePreset, deleteReflection, detachReflectionsForSession, exitWorkspace, isFavorite, library, moveWorkspace, ownerId, recordActivity, recordRecent, recordSavedSession, saveExercise, saveMetronomePreset, saveReflection, setWarmupProgress, setWeeklyGoal, startWorkspace, storageError, toggleFavorite, updateReflection, workspace]);

  const gateState = practiceLibraryGateState({
    loading: auth.loading,
    hasAuthSession: auth.hasAuthSession,
    hasProfile: auth.profile != null,
    hasLocalPracticeOwner: auth.localPracticeOwnerId != null,
    ownerReady,
  });
  if (gateState === 'recovery' || guestRecoveryState !== 'idle') {
    return (
      <UnresolvedIdentityRecovery
        retry={auth.refreshProfile}
        signOut={auth.signOut}
        continueAsGuest={auth.continueAsGuest}
        onGuestTransitionState={setGuestRecoveryState}
      />
    );
  }
  if (gateState === 'loading') {
    return <div className="route-loading" role="status">{t('loading.session')}</div>;
  }
  return <PracticeLibraryContext.Provider value={value}>{children}</PracticeLibraryContext.Provider>;
}

export function usePracticeLibrary(): PracticeLibraryState {
  const context = useContext(PracticeLibraryContext);
  if (!context) throw new Error('usePracticeLibrary must be used inside PracticeLibraryProvider');
  return context;
}
