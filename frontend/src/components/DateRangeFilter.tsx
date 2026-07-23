import { useI18n } from '../i18n/LocaleContext';

export function DateRangeFilter({
  value,
  onChange,
}: {
  value: { date_from: string; date_to: string };
  onChange: (range: { date_from: string; date_to: string }) => void;
}) {
  const { t } = useI18n();
  return (
    <div className="date-filter">
      <input type="date" value={value.date_from} onChange={(event) => onChange({ ...value, date_from: event.target.value })} aria-label={t('dateRange.from')} />
      <input type="date" value={value.date_to} onChange={(event) => onChange({ ...value, date_to: event.target.value })} aria-label={t('dateRange.to')} />
    </div>
  );
}
