import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

// Each option carries a short hint plus a 4-colour swatch (base / surface /
// accent / ink) so the picker can render a real preview of every look instead
// of a flat dropdown label.
export const themeOptions = [
  {
    value: 'system',
    label: 'System',
    hint: 'Match your device',
    swatch: { base: '#f7f7f5', surface: '#0b1118', accent: '#d8a53f', ink: '#8a94a0' },
  },
  {
    value: 'brass-white',
    label: 'White',
    hint: 'Clean and bright',
    swatch: { base: '#ffffff', surface: '#eef1f5', accent: '#b07d16', ink: '#10151b' },
  },
  {
    value: 'brass-day',
    label: 'Daylight',
    hint: 'Warm and light',
    swatch: { base: '#f7f3e9', surface: '#efe5d0', accent: '#b57916', ink: '#17202a' },
  },
  {
    value: 'brass-night',
    label: 'Midnight',
    hint: 'Dark and focused',
    swatch: { base: '#070a0f', surface: '#172330', accent: '#d8a53f', ink: '#f4f8fb' },
  },
  {
    value: 'liquid-clear',
    label: 'Liquid Clear',
    hint: 'Glassy and deep',
    swatch: { base: '#0a0f16', surface: '#14232f', accent: '#f0c970', ink: '#e8eef4' },
  },
  {
    value: 'liquid-tinted',
    label: 'Liquid Amber',
    hint: 'Warm glass tint',
    swatch: { base: '#12100a', surface: '#2d2313', accent: '#f0c970', ink: '#f4ecd8' },
  },
  {
    value: 'high-contrast',
    label: 'High Contrast',
    hint: 'Maximum legibility',
    swatch: { base: '#000000', surface: '#111111', accent: '#ffd65a', ink: '#ffffff' },
  },
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
