import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

export const themeOptions = [
  { value: 'system', label: 'System' },
  { value: 'brass-night', label: 'Brass Night' },
  { value: 'brass-day', label: 'Brass Day' },
  { value: 'liquid-clear', label: 'Liquid Brass - Clear' },
  { value: 'liquid-tinted', label: 'Liquid Brass - Tinted' },
  { value: 'high-contrast', label: 'High Contrast' },
] as const;

export type ThemePreference = (typeof themeOptions)[number]['value'];

interface ThemeState {
  theme: ThemePreference;
  resolvedTheme: Exclude<ThemePreference, 'system'>;
  setTheme: (theme: ThemePreference) => void;
}

const ThemeContext = createContext<ThemeState | null>(null);
const storageKey = 'brasstune.theme';

function isTheme(value: string | null): value is ThemePreference {
  return Boolean(value && themeOptions.some((option) => option.value === value));
}

function readStoredTheme(): ThemePreference {
  if (typeof window === 'undefined') return 'system';
  const stored = window.localStorage.getItem(storageKey);
  return isTheme(stored) ? stored : 'system';
}

function resolveTheme(theme: ThemePreference, prefersLight: boolean): Exclude<ThemePreference, 'system'> {
  if (theme !== 'system') return theme;
  return prefersLight ? 'brass-day' : 'brass-night';
}

function applyTheme(theme: ThemePreference, resolvedTheme: Exclude<ThemePreference, 'system'>) {
  if (typeof document === 'undefined') return;
  document.documentElement.dataset.themePreference = theme;
  document.documentElement.dataset.theme = resolvedTheme;
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<ThemePreference>(readStoredTheme);
  const [prefersLight, setPrefersLight] = useState(() => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia('(prefers-color-scheme: light)').matches;
  });
  const resolvedTheme = resolveTheme(theme, prefersLight);

  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: light)');
    const listener = (event: MediaQueryListEvent) => setPrefersLight(event.matches);
    media.addEventListener('change', listener);
    setPrefersLight(media.matches);
    return () => media.removeEventListener('change', listener);
  }, []);

  useEffect(() => {
    applyTheme(theme, resolvedTheme);
  }, [theme, resolvedTheme]);

  const setTheme = (nextTheme: ThemePreference) => {
    setThemeState(nextTheme);
    window.localStorage.setItem(storageKey, nextTheme);
    applyTheme(nextTheme, resolveTheme(nextTheme, window.matchMedia('(prefers-color-scheme: light)').matches));
  };

  const value = useMemo(() => ({ theme, resolvedTheme, setTheme }), [theme, resolvedTheme]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  const value = useContext(ThemeContext);
  if (!value) {
    throw new Error('useTheme must be used within ThemeProvider');
  }
  return value;
}
