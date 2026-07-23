import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import { IntlProvider, useIntl, type PrimitiveType } from 'react-intl';
import {
  bootstrapMessagesForLocale,
  englishMessages,
  type MessageCatalog,
  type MessageId,
} from './messages.base';

export const LOCALE_STORAGE_KEY = 'brasstune.locale';

export const productionLocales = [
  'en', 'es', 'zh-Hans', 'zh-Hant', 'ar', 'fr', 'de', 'ru', 'pt-BR', 'ja', 'ko', 'vi',
] as const;

export const localeOptions = [
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Español' },
  { value: 'zh-Hans', label: '简体中文' },
  { value: 'zh-Hant', label: '繁體中文' },
  { value: 'ar', label: 'العربية' },
  { value: 'fr', label: 'Français' },
  { value: 'de', label: 'Deutsch' },
  { value: 'ru', label: 'Русский' },
  { value: 'pt-BR', label: 'Português (Brasil)' },
  { value: 'ja', label: '日本語' },
  { value: 'ko', label: '한국어' },
  { value: 'vi', label: 'Tiếng Việt' },
  { value: 'en-XA', label: 'Pseudo (QA)' },
] as const;

export type ProductionLocale = (typeof productionLocales)[number];
export type AppLocale = (typeof localeOptions)[number]['value'];

const localeValues = new Set<string>(localeOptions.map((option) => option.value));
const catalogLoaders = {
  es: () => import('./catalogs/locale-es'),
  'zh-Hans': () => import('./catalogs/locale-zh-Hans'),
  'zh-Hant': () => import('./catalogs/locale-zh-Hant'),
  ar: () => import('./catalogs/locale-ar'),
  fr: () => import('./catalogs/locale-fr'),
  de: () => import('./catalogs/locale-de'),
  ru: () => import('./catalogs/locale-ru'),
  'pt-BR': () => import('./catalogs/locale-pt-BR'),
  ja: () => import('./catalogs/locale-ja'),
  ko: () => import('./catalogs/locale-ko'),
  vi: () => import('./catalogs/locale-vi'),
} satisfies Record<Exclude<ProductionLocale, 'en'>, () => Promise<{ default: MessageCatalog }>>;

export function normalizeLocale(value: string | null | undefined): AppLocale | null {
  if (!value) return null;
  const normalized = value.replace(/_/g, '-');
  if (localeValues.has(normalized)) return normalized as AppLocale;
  const lower = normalized.toLowerCase();
  if (lower.startsWith('zh')) {
    if (/^zh-(?:hant|tw|hk|mo)(?:-|$)/.test(lower)) return 'zh-Hant';
    return 'zh-Hans';
  }
  if (lower.startsWith('pt')) return 'pt-BR';
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

export async function loadMessagesForLocale(locale: AppLocale): Promise<MessageCatalog> {
  if (locale === 'en' || locale === 'en-XA') return bootstrapMessagesForLocale(locale);
  return (await catalogLoaders[locale]()).default;
}

interface LocaleState {
  locale: AppLocale;
  dir: 'ltr' | 'rtl';
  setLocale: (locale: AppLocale) => void;
}

interface LoadedCatalog {
  locale: AppLocale;
  messages: MessageCatalog;
}

const LocaleStateContext = createContext<LocaleState | null>(null);

function manifestPath(locale: AppLocale): string {
  return locale === 'en' ? '/manifest.webmanifest' : `/manifests/${locale}.webmanifest`;
}

export function LocaleProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<AppLocale>(initialLocale);
  const immediatelyAvailable = locale === 'en' || locale === 'en-XA';
  const [catalog, setCatalog] = useState<LoadedCatalog>(() => ({
    locale: immediatelyAvailable ? locale : 'en',
    messages: bootstrapMessagesForLocale(immediatelyAvailable ? locale : 'en'),
  }));
  const [loading, setLoading] = useState(!immediatelyAvailable);
  const dir: LocaleState['dir'] = catalog.locale === 'ar' ? 'rtl' : 'ltr';

  useEffect(() => {
    let active = true;
    setLoading(true);
    loadMessagesForLocale(locale)
      .then((messages) => {
        if (!active) return;
        setCatalog({ locale, messages });
        setLoading(false);
      })
      .catch(() => {
        if (!active) return;
        setCatalog({ locale: 'en', messages: englishMessages });
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [locale]);

  useEffect(() => {
    document.documentElement.lang = catalog.locale;
    document.documentElement.dir = dir;
    document.title = catalog.messages['meta.title'];
    document.querySelector('meta[name="description"]')?.setAttribute('content', catalog.messages['meta.description']);
    document.querySelector<HTMLLinkElement>('link[rel="manifest"]')?.setAttribute('href', manifestPath(catalog.locale));
  }, [catalog, dir]);

  useEffect(() => {
    window.localStorage.setItem(LOCALE_STORAGE_KEY, locale);
  }, [locale]);

  const setLocale = (value: AppLocale) => {
    if (localeValues.has(value)) setLocaleState(value);
  };
  const state = useMemo(() => ({ locale, dir, setLocale }), [dir, locale]);
  const intlLocale = catalog.locale === 'en-XA' ? 'en' : catalog.locale;

  return (
    <IntlProvider locale={intlLocale} defaultLocale="en" messages={catalog.messages}>
      <LocaleStateContext.Provider value={state}>
        {loading ? <div className="app-loading" role="status">{englishMessages['loading.locale']}</div> : children}
      </LocaleStateContext.Provider>
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
