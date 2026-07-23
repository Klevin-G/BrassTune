import { localeOptions, type AppLocale, useI18n } from '../i18n/LocaleContext';

export function LocaleSelector() {
  const { locale, setLocale, t } = useI18n();
  return (
    <label className="field locale-selector">
      <span>{t('locale.label')}</span>
      <select value={locale} onChange={(event) => setLocale(event.target.value as AppLocale)}>
        {localeOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    </label>
  );
}
