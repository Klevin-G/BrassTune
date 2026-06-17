export function DateRangeFilter({
  value,
  onChange,
}: {
  value: { date_from: string; date_to: string };
  onChange: (range: { date_from: string; date_to: string }) => void;
}) {
  return (
    <div className="date-filter">
      <input type="date" value={value.date_from} onChange={(event) => onChange({ ...value, date_from: event.target.value })} aria-label="Date from" />
      <input type="date" value={value.date_to} onChange={(event) => onChange({ ...value, date_to: event.target.value })} aria-label="Date to" />
    </div>
  );
}
