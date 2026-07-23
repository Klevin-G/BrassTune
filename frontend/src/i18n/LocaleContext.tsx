import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
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

// Pseudo-localization remains a supported programmatic QA locale, but should
// never be offered as a production user setting.
export const productionLocaleOptions = localeOptions.filter((option) => option.value !== 'en-XA');

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
  const [requestedLocale, setRequestedLocale] = useState<AppLocale>(initialLocale);
  const immediatelyAvailable = requestedLocale === 'en' || requestedLocale === 'en-XA';
  const [catalog, setCatalog] = useState<LoadedCatalog>(() => ({
    locale: immediatelyAvailable ? requestedLocale : 'en',
    messages: bootstrapMessagesForLocale(immediatelyAvailable ? requestedLocale : 'en'),
  }));
  const [loading, setLoading] = useState(!immediatelyAvailable);
  const [failedLocale, setFailedLocale] = useState<AppLocale | null>(null);
  const dir: LocaleState['dir'] = catalog.locale === 'ar' ? 'rtl' : 'ltr';

  useEffect(() => {
    let active = true;
    setLoading(true);
    loadMessagesForLocale(requestedLocale)
      .then((messages) => {
        if (!active) return;
        setCatalog({ locale: requestedLocale, messages });
        setLoading(false);
      })
      .catch(() => {
        if (!active) return;
        // Commit the active catalog, selector, document metadata, direction,
        // and persisted choice to one known-good locale. Never leave a broken
        // selection pointing at an English catalog.
        setCatalog({ locale: 'en', messages: englishMessages });
        setRequestedLocale('en');
        setFailedLocale(requestedLocale);
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [requestedLocale]);

  useEffect(() => {
    document.documentElement.lang = catalog.locale;
    document.documentElement.dir = dir;
    document.title = catalog.messages['meta.title'];
    document.querySelector('meta[name="description"]')?.setAttribute('content', catalog.messages['meta.description']);
    document.querySelector<HTMLLinkElement>('link[rel="manifest"]')?.setAttribute('href', manifestPath(catalog.locale));
    try { window.localStorage.setItem(LOCALE_STORAGE_KEY, catalog.locale); } catch { /* device storage unavailable */ }
  }, [catalog, dir]);

  const setLocale = (value: AppLocale) => {
    if (!localeValues.has(value)) return;
    setFailedLocale(null);
    setRequestedLocale(value);
  };
  const retryFailedLocale = useCallback(() => {
    if (!failedLocale) return;
    const retryLocale = failedLocale;
    setFailedLocale(null);
    try {
      // Browsers cache failed module imports for the lifetime of the document.
      // Persist the requested locale and reload so the retry gets a fresh
      // module registry instead of immediately replaying the cached rejection.
      window.localStorage.setItem(LOCALE_STORAGE_KEY, retryLocale);
      window.location.reload();
    } catch {
      setRequestedLocale(retryLocale);
    }
  }, [failedLocale]);
  const state = useMemo(() => ({ locale: catalog.locale, dir, setLocale }), [catalog.locale, dir]);
  const intlLocale = catalog.locale === 'en-XA' ? 'en' : catalog.locale;

  return (
    <IntlProvider locale={intlLocale} defaultLocale="en" messages={catalog.messages}>
      <LocaleStateContext.Provider value={state}>
        {loading ? <div className="app-loading" role="status">{englishMessages['loading.locale']}</div> : (
          <>
            {failedLocale && (
              <div className="locale-load-error" role="alert">
                <span>{englishMessages['locale.loadError']}</span>
                <button type="button" className="ghost-button" onClick={retryFailedLocale}>{englishMessages['locale.retry']}</button>
              </div>
            )}
            {children}
          </>
        )}
      </LocaleStateContext.Provider>
    </IntlProvider>
  );
}

export function useI18n() {
  const state = useContext(LocaleStateContext);
  const intl = useIntl();
  const t = useCallback(
    (id: MessageId, values?: Record<string, PrimitiveType>) => intl.formatMessage({ id, defaultMessage: englishMessages[id] }, values),
    [intl],
  );
  if (!state) throw new Error('useI18n must be used within LocaleProvider');
  return {
    ...state,
    t,
    formatDate: (value: Date | number | string, options?: Intl.DateTimeFormatOptions) => intl.formatDate(value, options),
    formatNumber: (value: number, options?: Intl.NumberFormatOptions) => intl.formatNumber(value, options),
    formatList: (values: string[], options?: { type?: 'conjunction' | 'disjunction' | 'unit'; style?: 'long' | 'short' | 'narrow' }) => intl.formatList(values, options) as string,
  };
}
