import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { IntlProvider, useIntl, type PrimitiveType } from 'react-intl';
import { englishMessages, messagesForLocale, type MessageId } from './messages';

export const LOCALE_STORAGE_KEY = 'brasstune.locale';

export const localeOptions = [
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Español' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' },
  { value: 'it', label: 'Italiano' },
  { value: 'pt-BR', label: 'Português (Brasil)' },
  { value: 'ar', label: 'العربية' },
  { value: 'hi', label: 'हिन्दी' },
  { value: 'ja', label: '日本語' },
  { value: 'ko', label: '한국어' },
  { value: 'zh-CN', label: '简体中文' },
  { value: 'en-XA', label: 'Pseudo (QA)' },
] as const;

export type AppLocale = (typeof localeOptions)[number]['value'];

const localeValues = new Set<string>(localeOptions.map((option) => option.value));

export function normalizeLocale(value: string | null | undefined): AppLocale | null {
  if (!value) return null;
  const normalized = value.replace('_', '-');
  if (localeValues.has(normalized)) return normalized as AppLocale;
  const lower = normalized.toLowerCase();
  if (lower.startsWith('pt')) return 'pt-BR';
  if (lower.startsWith('zh')) return 'zh-CN';
  const language = lower.split('-')[0];
  return localeOptions.find((option) => option.value.toLowerCase() === language)?.value ?? null;
}

function initialLocale(): AppLocale {
  if (typeof window === 'undefined') return 'en';
  const stored = normalizeLocale(window.localStorage.getItem(LOCALE_STORAGE_KEY));
  if (stored) return stored;
  for (const candidate of navigator.languages ?? [navigator.language]) {
    const matched = normalizeLocale(candidate);
    if (matched && matched !== 'en-XA') return matched;
  }
  return 'en';
}

interface LocaleState {
  locale: AppLocale;
  dir: 'ltr' | 'rtl';
  setLocale: (locale: AppLocale) => void;
}

const LocaleStateContext = createContext<LocaleState | null>(null);

function manifestPath(locale: AppLocale): string {
  return locale === 'en' ? '/manifest.webmanifest' : `/manifests/${locale}.webmanifest`;
}

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<AppLocale>(initialLocale);
  const dir: LocaleState['dir'] = locale === 'ar' ? 'rtl' : 'ltr';
  const messages = useMemo(() => messagesForLocale(locale), [locale]);

  useEffect(() => {
    document.documentElement.lang = locale;
    document.documentElement.dir = dir;
    document.title = messages['meta.title'];
    document.querySelector('meta[name="description"]')?.setAttribute('content', messages['meta.description']);
    document.querySelector<HTMLLinkElement>('link[rel="manifest"]')?.setAttribute('href', manifestPath(locale));
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  }, [dir, locale, messages]);

  const setLocale = (value: AppLocale) => {
    if (localeValues.has(value)) setLocaleState(value);
  };
  const state = useMemo(() => ({ locale, dir, setLocale }), [dir, locale]);

  return (
    <IntlProvider locale={locale === 'en-XA' ? 'en' : locale} defaultLocale="en" messages={messages}>
      <LocaleStateContext.Provider value={state}>{children}</LocaleStateContext.Provider>
    </IntlProvider>
  );
}

export function useI18n() {
  const state = useContext(LocaleStateContext);
  const intl = useIntl();
  if (!state) throw new Error('useI18n must be used within LocaleProvider');
  return {
    ...state,
    t: (id: MessageId, values?: Record<string, PrimitiveType>) => intl.formatMessage({ id, defaultMessage: englishMessages[id] }, values),
    formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => intl.formatDate(value, options),
    formatNumber: (value: number, options?: Intl.NumberFormatOptions) => intl.formatNumber(value, options),
    formatList: (values: string[], options?: { type?: 'conjunction' | 'disjunction' | 'unit'; style?: 'long' | 'short' | 'narrow' }) => intl.formatList(values, options) as string,
  };
}
