export function DateRangeFilter({ onChange }: { onChange?: (range: { from: string; to: string }) => void }) {
  return (
    <div className="date-filter">
      <input type="date" onChange={(event) => onChange?.({ from: event.target.value, to: '' })} />
      <input type="date" onChange={(event) => onChange?.({ from: '', to: event.target.value })} />
    </div>
  );
}

