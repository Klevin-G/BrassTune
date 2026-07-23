import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { updateCurrentUser } from '../api/client';
import { useAuth } from './AuthContext';

const legacyOnboardingCompleteKey = 'brasstune.onboardingComplete';
const guestOnboardingCompleteKey = 'brasstune.guestOnboardingComplete';
export const MIN_REFERENCE_PITCH = 430;
export const MAX_REFERENCE_PITCH = 450;

export function clampReferencePitch(value: number): number | null {
  if (!Number.isFinite(value)) return null;
  return Math.min(MAX_REFERENCE_PITCH, Math.max(MIN_REFERENCE_PITCH, value));
}

interface AccountOnboardingInput {
  authLoading: boolean;
  hasAuthSession: boolean;
  isSignedIn: boolean;
  onboardingCompletedAt?: string | null;
}

export function accountOnboardingDecision(input: AccountOnboardingInput) {
  if (input.authLoading || !input.hasAuthSession || !input.isSignedIn) return null;
  const completed = Boolean(input.onboardingCompletedAt);
  return { completed, open: !completed };
}

interface AppSettings {
  instrumentId: string;
  setInstrumentId: (value: string) => void;
  referencePitch: number;
  setReferencePitch: (value: number) => void;
  demoMode: boolean;
  setDemoMode: (value: boolean) => void;
  onboardingOpen: boolean;
  onboardingComplete: boolean;
  onboardingSaving: boolean;
  onboardingSaveError: string | null;
  openOnboarding: () => void;
  closeOnboarding: () => void;
  completeOnboarding: () => Promise<boolean>;
  retryOnboardingCompletion: () => Promise<boolean>;
}

const AppSettingsContext = createContext<AppSettings | null>(null);

export function AppSettingsProvider({ children }: { children: React.ReactNode }) {
  const auth = useAuth();
  const [instrumentId, setInstrumentId] = useState(() => localStorage.getItem('brasstune.instrument') ?? 'trumpet');
  const [referencePitch, setReferencePitchState] = useState(() => {
    const stored = Number(localStorage.getItem('brasstune.referencePitch') ?? 440);
    return clampReferencePitch(stored) ?? 440;
  });
  // Real microphone by default; the guided-audio demo is an explicit opt-in.
  const [demoMode, setDemoModeState] = useState(() => localStorage.getItem('brasstune.demoMode') === 'true');
  // Keep the dialog closed until account restoration has settled. The effect
  // below then makes an audience-aware decision for an account or a guest.
  const [onboardingComplete, setOnboardingComplete] = useState(false);
  const [onboardingOpen, setOnboardingOpen] = useState(false);
  const [onboardingSaving, setOnboardingSaving] = useState(false);
  const [onboardingSaveError, setOnboardingSaveError] = useState<string | null>(null);
  const handledGuestEntrySequence = useRef(0);
  const onboardingSaveInFlight = useRef(false);

  const setReferencePitch = useCallback((value: number) => {
    const clamped = clampReferencePitch(value);
    if (clamped === null) return;
    setReferencePitchState(clamped);
    localStorage.setItem('brasstune.referencePitch', String(clamped));
  }, []);
  const setInstrumentIdPersisted = useCallback((value: string) => {
    setInstrumentId(value);
    localStorage.setItem('brasstune.instrument', value);
  }, []);
  const setDemoMode = useCallback((value: boolean) => {
    setDemoModeState(value);
    localStorage.setItem('brasstune.demoMode', String(value));
  }, []);
  const openOnboarding = useCallback(() => {
    setOnboardingSaveError(null);
    setOnboardingOpen(true);
  }, []);
  const closeOnboarding = useCallback(() => {
    // Closing is intentionally temporary. New users should see the tour again
    // after a reload until they finish the last step and its completion saves.
    setOnboardingSaveError(null);
    setOnboardingOpen(false);
  }, []);
  const completeOnboarding = useCallback(async () => {
    if (onboardingSaveInFlight.current) return false;
    onboardingSaveInFlight.current = true;
    setOnboardingSaving(true);
    setOnboardingSaveError(null);
    try {
      if (auth.isSignedIn) {
        await updateCurrentUser({ onboarding_completed: true, primary_instrument_id: instrumentId });
        await auth.refreshProfile();
      } else if (auth.guestMode) {
        localStorage.setItem(guestOnboardingCompleteKey, 'true');
      } else {
        throw new Error('Start as a guest or sign in before finishing the tour.');
      }
      localStorage.setItem(legacyOnboardingCompleteKey, 'true');
      setOnboardingComplete(true);
      setOnboardingOpen(false);
      return true;
    } catch {
      setOnboardingComplete(false);
      setOnboardingOpen(true);
      setOnboardingSaveError('We couldn’t save that you finished the tour. Your choices are still here—try saving again.');
      return false;
    } finally {
      onboardingSaveInFlight.current = false;
      setOnboardingSaving(false);
    }
  }, [auth.guestMode, auth.isSignedIn, auth.refreshProfile, instrumentId]);
  const retryOnboardingCompletion = completeOnboarding;

  useEffect(() => {
    if (auth.loading) return;

    if (auth.hasAuthSession) {
      // A signed-in profile is the source of truth. AppShell keeps the tour
      // unmounted while that profile is still being restored.
      const accountDecision = accountOnboardingDecision({
        authLoading: auth.loading,
        hasAuthSession: auth.hasAuthSession,
        isSignedIn: auth.isSignedIn,
        onboardingCompletedAt: auth.profile?.onboarding_completed_at,
      });
      if (!accountDecision) {
        setOnboardingOpen(false);
        return;
      }
      setOnboardingComplete(accountDecision.completed);
      setOnboardingOpen(accountDecision.open);
      setOnboardingSaveError(null);
      if (accountDecision.completed) {
        localStorage.setItem(legacyOnboardingCompleteKey, 'true');
      }
      return;
    }

    if (!auth.guestMode) {
      setOnboardingComplete(false);
      setOnboardingOpen(false);
      setOnboardingSaveError(null);
      return;
    }

    if (auth.guestEntrySequence > handledGuestEntrySequence.current) {
      // Every explicit guest entry starts a fresh tour, even on a browser
      // whose legacy shared flag says that another audience completed it.
      handledGuestEntrySequence.current = auth.guestEntrySequence;
      localStorage.setItem(guestOnboardingCompleteKey, 'false');
      setOnboardingComplete(false);
      setOnboardingOpen(true);
      setOnboardingSaveError(null);
      return;
    }

    const guestCompletion = localStorage.getItem(guestOnboardingCompleteKey);
    const completed = guestCompletion === null
      ? localStorage.getItem(legacyOnboardingCompleteKey) === 'true'
      : guestCompletion === 'true';
    setOnboardingComplete(completed);
    setOnboardingOpen(!completed);
  }, [
    auth.guestEntrySequence,
    auth.guestMode,
    auth.hasAuthSession,
    auth.isSignedIn,
    auth.loading,
    auth.profile?.onboarding_completed_at,
    auth.session?.user.id,
  ]);

  const value = useMemo(
    () => ({
      instrumentId,
      setInstrumentId: setInstrumentIdPersisted,
      referencePitch,
      setReferencePitch,
      demoMode,
      setDemoMode,
      onboardingOpen,
      onboardingComplete,
      onboardingSaving,
      onboardingSaveError,
      openOnboarding,
      closeOnboarding,
      completeOnboarding,
      retryOnboardingCompletion,
    }),
    [closeOnboarding, completeOnboarding, demoMode, instrumentId, onboardingComplete, onboardingOpen, onboardingSaveError, onboardingSaving, openOnboarding, referencePitch, retryOnboardingCompletion, setDemoMode, setInstrumentIdPersisted, setReferencePitch],
  );
  return <AppSettingsContext.Provider value={value}>{children}</AppSettingsContext.Provider>;
}

export function useAppSettings() {
  const value = useContext(AppSettingsContext);
  if (!value) {
    throw new Error('useAppSettings must be used within AppSettingsProvider');
  }
  return value;
}
