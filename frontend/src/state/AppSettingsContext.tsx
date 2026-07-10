import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import { updateCurrentUser } from '../api/client';
import { useAuth } from './AuthContext';

interface AppSettings {
  instrumentId: string;
  setInstrumentId: (value: string) => void;
  referencePitch: number;
  setReferencePitch: (value: number) => void;
  demoMode: boolean;
  setDemoMode: (value: boolean) => void;
  onboardingOpen: boolean;
  onboardingComplete: boolean;
  openOnboarding: () => void;
  closeOnboarding: () => void;
  completeOnboarding: () => void;
}

const AppSettingsContext = createContext<AppSettings | null>(null);

export function AppSettingsProvider({ children }: { children: React.ReactNode }) {
  const auth = useAuth();
  const [instrumentId, setInstrumentId] = useState(() => localStorage.getItem('brasstune.instrument') ?? 'trumpet');
  const [referencePitch, setReferencePitchState] = useState(() => Number(localStorage.getItem('brasstune.referencePitch') ?? 440));
  // Real microphone by default; the guided-audio demo is an explicit opt-in.
  const [demoMode, setDemoModeState] = useState(() => localStorage.getItem('brasstune.demoMode') === 'true');
  const [onboardingComplete, setOnboardingComplete] = useState(() => localStorage.getItem('brasstune.onboardingComplete') === 'true');
  const [onboardingOpen, setOnboardingOpen] = useState(() => localStorage.getItem('brasstune.onboardingComplete') !== 'true');

  const setReferencePitch = (value: number) => {
    setReferencePitchState(value);
    localStorage.setItem('brasstune.referencePitch', String(value));
  };
  const setInstrumentIdPersisted = (value: string) => {
    setInstrumentId(value);
    localStorage.setItem('brasstune.instrument', value);
  };
  const setDemoMode = (value: boolean) => {
    setDemoModeState(value);
    localStorage.setItem('brasstune.demoMode', String(value));
  };
  const openOnboarding = () => setOnboardingOpen(true);
  const closeOnboarding = () => {
    // Dismissing the tour (X / Escape) counts as done for this device, so it
    // does not re-open on every reload.
    setOnboardingOpen(false);
    setOnboardingComplete(true);
    localStorage.setItem('brasstune.onboardingComplete', 'true');
  };
  const completeOnboarding = () => {
    setOnboardingComplete(true);
    setOnboardingOpen(false);
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    updateCurrentUser({ onboarding_completed: true, primary_instrument_id: instrumentId }).catch(() => undefined);
  };

  useEffect(() => {
    if (auth.profile?.onboarding_completed_at) {
      setOnboardingComplete(true);
      setOnboardingOpen(false);
      localStorage.setItem('brasstune.onboardingComplete', 'true');
    }
  }, [auth.profile?.onboarding_completed_at]);

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
      openOnboarding,
      closeOnboarding,
      completeOnboarding,
    }),
    [instrumentId, referencePitch, demoMode, onboardingOpen, onboardingComplete],
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
