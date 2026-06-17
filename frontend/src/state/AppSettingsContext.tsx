import { createContext, useContext, useMemo, useState } from 'react';

interface AppSettings {
  instrumentId: string;
  setInstrumentId: (value: string) => void;
  referencePitch: number;
  setReferencePitch: (value: number) => void;
  demoMode: boolean;
  setDemoMode: (value: boolean) => void;
}

const AppSettingsContext = createContext<AppSettings | null>(null);

export function AppSettingsProvider({ children }: { children: React.ReactNode }) {
  const [instrumentId, setInstrumentId] = useState(() => localStorage.getItem('brasstune.instrument') ?? 'trumpet');
  const [referencePitch, setReferencePitchState] = useState(() => Number(localStorage.getItem('brasstune.referencePitch') ?? 440));
  const [demoMode, setDemoModeState] = useState(() => localStorage.getItem('brasstune.demoMode') !== 'false');

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

  const value = useMemo(
    () => ({ instrumentId, setInstrumentId: setInstrumentIdPersisted, referencePitch, setReferencePitch, demoMode, setDemoMode }),
    [instrumentId, referencePitch, demoMode],
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

