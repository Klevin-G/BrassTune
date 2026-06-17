import type { NoteStats } from '../domain/types';

export function HeatMapGrid({ rows, compact = false }: { rows: NoteStats[]; compact?: boolean }) {
  const sorted = [...rows].sort((a, b) => a.written_octave - b.written_octave || a.note_label.localeCompare(b.note_label));
  return (
    <div className={`heatmap ${compact ? 'compact' : ''}`}>
      {sorted.length === 0 && <p className="empty-state">No heat map data yet.</p>}
      {sorted.map((row) => (
        <button className={`heat-cell ${row.severity_color ?? 'insufficient'}`} key={row.note_label} title={`${row.note_label}: ${Math.round(row.avg_abs_cents)} cents avg abs`}>
          <strong>{row.note_label}</strong>
          {!compact && <span>{Math.round(row.avg_signed_cents)}c</span>}
        </button>
      ))}
    </div>
  );
}

