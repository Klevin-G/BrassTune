import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  PRACTICE_LIBRARY_VERSION,
  emptyPracticeLibrary,
  normalizeMetronomePreset,
  ownerWorkspaceKey,
  practiceLibraryLimits,
  readPracticeLibrary,
  removeCustomExercise,
  removeMetronomePreset,
  resolvePracticeOwner,
  upsertById,
  writePracticeLibrary,
  type CustomExercise,
  type MetronomePreset,
  type PracticeLibrary,
  type PracticePack,
  type PracticeReflection,
  type PracticeTarget,
  type PracticeWorkspace,
  type WarmupProgress,
} from '../domain/practiceLibrary';
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
  saveReflection: (text: string, sessionId?: string) => PracticeReflection | null;
  updateReflection: (id: string, text: string) => boolean;
  deleteReflection: (id: string) => void;
  setWarmupProgress: (progress: Pick<WarmupProgress, 'elapsedSeconds' | 'stepIndex'>) => void;
  startWorkspace: (pack: PracticePack) => void;
  moveWorkspace: (stepIndex: number) => void;
  exitWorkspace: () => void;
}

const PracticeLibraryContext = createContext<PracticeLibraryState | null>(null);

interface LoadedPracticeState {
  ownerId: string | null;
  library: PracticeLibrary;
  workspace: PracticeWorkspace | null;
}

export function practiceLibraryGateState({
  loading,
  hasAuthSession,
  hasProfile,
  ownerReady,
}: {
  loading: boolean;
  hasAuthSession: boolean;
  hasProfile: boolean;
  ownerReady: boolean;
}): 'loading' | 'recovery' | 'ready' {
  if (loading) return 'loading';
  if (hasAuthSession && !hasProfile) return 'recovery';
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
    if (!raw) return null;
    const value = JSON.parse(raw) as PracticeWorkspace;
    if (!value?.pack?.id || !Array.isArray(value.pack.steps) || value.pack.steps.length < 1 || value.pack.steps.length > 12) return null;
    const stepIndex = Math.max(0, Math.min(value.pack.steps.length - 1, Math.round(Number(value.stepIndex) || 0)));
    return { ...value, stepIndex };
  } catch {
    return null;
  }
}

function UnresolvedIdentityRecovery({
  retry,
  signOut,
  continueAsGuest,
}: {
  retry: () => Promise<void>;
  signOut: () => Promise<void>;
  continueAsGuest: () => void;
}) {
  const { t } = useI18n();
  const [busyAction, setBusyAction] = useState<'retry' | 'sign-out' | 'guest' | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

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

  const leaveAccount = async (asGuest: boolean) => {
    if (busyAction) return;
    setBusyAction(asGuest ? 'guest' : 'sign-out');
    setActionError(null);
    try {
      await signOut();
    } catch {
      if (!asGuest) setActionError(t('settings.signOutFailed'));
    } finally {
      if (asGuest) continueAsGuest();
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
          <button className="ghost-button" type="button" disabled={busyAction != null} onClick={() => void leaveAccount(false)}>
            {t('settings.signOut')}
          </button>
          <button className="ghost-button" type="button" disabled={busyAction != null} onClick={() => void leaveAccount(true)}>
            {t('auth.continueGuest')}
          </button>
        </div>
      </section>
    </main>
  );
}

export function PracticeLibraryProvider({ children }: { children: ReactNode }) {
  const auth = useAuth();
  const { t } = useI18n();
  const ownerId = resolvePracticeOwner({ loading: auth.loading, hasAuthSession: auth.hasAuthSession, isSignedIn: auth.isSignedIn, profileId: auth.profile?.id });
  const [loadedState, setLoadedState] = useState<LoadedPracticeState>(() => ({
    ownerId,
    library: ownerId ? readPracticeLibrary(localStorage, ownerId) : emptyPracticeLibrary(),
    workspace: ownerId ? readWorkspace(ownerId) : null,
  }));
  const [storageError, setStorageError] = useState<string | null>(null);
  const ownerReady = ownerId != null && loadedState.ownerId === ownerId;
  const library = loadedState.library;
  const workspace = loadedState.workspace;

  useEffect(() => {
    setLoadedState({
      ownerId,
      library: ownerId ? readPracticeLibrary(localStorage, ownerId) : emptyPracticeLibrary(),
      workspace: ownerId ? readWorkspace(ownerId) : null,
    });
    setStorageError(null);
  }, [ownerId]);

  const updateLibrary = useCallback((update: (current: PracticeLibrary) => PracticeLibrary) => {
    setLoadedState((current) => {
      if (!ownerId || current.ownerId !== ownerId) return current;
      const next = update(current.library);
      const saved = writePracticeLibrary(localStorage, ownerId, next);
      setStorageError(saved ? null : 'This device is out of browser storage. Your latest practice-library change could not be saved.');
      return saved ? { ...current, library: next } : current;
    });
  }, [ownerId]);

  const saveExercise = useCallback((exercise: Omit<CustomExercise, 'id' | 'createdAt'> & { id?: string }) => {
    const item: CustomExercise = {
      id: exercise.id ?? createId('exercise'),
      name: exercise.name.trim().slice(0, 60),
      notes: exercise.notes.slice(0, 32),
      source: exercise.source,
      createdAt: new Date().toISOString(),
    };
    updateLibrary((current) => ({ ...current, customExercises: upsertById(current.customExercises, item, practiceLibraryLimits.customExercises) }));
    return item;
  }, [updateLibrary]);

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
    updateLibrary((current) => ({
      ...current,
      weeklyGoal: {
        ...current.weeklyGoal,
        completedMinutes: Math.min(10_000, current.weeklyGoal.completedMinutes + Math.max(1, Math.round(minutes) || 1)),
        completedSessions: Math.min(1_000, current.weeklyGoal.completedSessions + 1),
      },
    }));
  }, [updateLibrary]);

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

  const setWarmupProgress = useCallback((progress: Pick<WarmupProgress, 'elapsedSeconds' | 'stepIndex'>) => {
    updateLibrary((current) => ({
      ...current,
      warmup: {
        elapsedSeconds: Math.max(0, Math.min(300, Math.round(progress.elapsedSeconds))),
        stepIndex: Math.max(0, Math.min(4, Math.round(progress.stepIndex))),
        updatedAt: new Date().toISOString(),
      },
    }));
  }, [updateLibrary]);

  const persistWorkspace = useCallback((next: PracticeWorkspace | null) => {
    setLoadedState((current) => {
      if (!ownerId || current.ownerId !== ownerId) return current;
      try {
        if (next) sessionStorage.setItem(ownerWorkspaceKey(ownerId), JSON.stringify(next));
        else sessionStorage.removeItem(ownerWorkspaceKey(ownerId));
      } catch {
        setStorageError('Focused mode will work for this page, but this browser could not remember it between pages.');
      }
      return { ...current, workspace: next };
    });
  }, [ownerId]);

  const startWorkspace = useCallback((pack: PracticePack) => {
    persistWorkspace({ pack, stepIndex: 0, startedAt: new Date().toISOString() });
  }, [persistWorkspace]);

  const moveWorkspace = useCallback((stepIndex: number) => {
    if (!workspace) return;
    persistWorkspace({ ...workspace, stepIndex: Math.max(0, Math.min(workspace.pack.steps.length - 1, stepIndex)) });
  }, [persistWorkspace, workspace]);

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
    saveReflection,
    updateReflection,
    deleteReflection,
    setWarmupProgress,
    startWorkspace,
    moveWorkspace,
    exitWorkspace,
  }), [deleteExercise, deleteMetronomePreset, deleteReflection, exitWorkspace, isFavorite, library, moveWorkspace, ownerId, recordActivity, recordRecent, saveExercise, saveMetronomePreset, saveReflection, setWarmupProgress, setWeeklyGoal, startWorkspace, storageError, toggleFavorite, updateReflection, workspace]);

  const gateState = practiceLibraryGateState({
    loading: auth.loading,
    hasAuthSession: auth.hasAuthSession,
    hasProfile: auth.profile != null,
    ownerReady,
  });
  if (gateState === 'loading') {
    return <div className="route-loading" role="status">{t('loading.session')}</div>;
  }
  if (gateState === 'recovery') {
    return (
      <UnresolvedIdentityRecovery
        retry={auth.refreshProfile}
        signOut={auth.signOut}
        continueAsGuest={auth.continueAsGuest}
      />
    );
  }
  return <PracticeLibraryContext.Provider value={value}>{children}</PracticeLibraryContext.Provider>;
}

export function usePracticeLibrary(): PracticeLibraryState {
  const context = useContext(PracticeLibraryContext);
  if (!context) throw new Error('usePracticeLibrary must be used inside PracticeLibraryProvider');
  return context;
}
