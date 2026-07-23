import type { NoteStats } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';

const noteOrder = ['C', 'C#', 'Db', 'D', 'D#', 'Eb', 'E', 'F', 'F#', 'Gb', 'G', 'G#', 'Ab', 'A', 'A#', 'Bb', 'B'];

function noteSortValue(row: NoteStats) {
  return row.written_octave * 100 + Math.max(0, noteOrder.indexOf(row.written_note));
}

export function HeatMapGrid({
  rows,
  compact = false,
  selectedNote,
  onSelect,
}: {
  rows: NoteStats[];
  compact?: boolean;
  selectedNote?: string;
  onSelect?: (row: NoteStats) => void;
}) {
  const { t, formatNumber } = useI18n();
  const sorted = [...rows].sort((a, b) => noteSortValue(a) - noteSortValue(b) || a.note_label.localeCompare(b.note_label));
  return (
    <div className={`heatmap ${compact ? 'compact' : ''}`}>
      {sorted.length === 0 && <p className="empty-state">{t('heatmap.empty')}</p>}
      {sorted.map((row) => {
        const detail = row.has_data === false
          ? t('heatmap.noAttempts')
          : t('heatmap.detail', {
              signed: formatNumber(row.avg_signed_cents, { maximumFractionDigits: 1 }),
              absolute: formatNumber(row.avg_abs_cents, { maximumFractionDigits: 1 }),
              percent: formatNumber(Math.round(row.in_tune_percentage)),
              seconds: formatNumber(Math.round(row.duration_seconds)),
              summary: row.recommendation_summary ?? row.severity,
            });
        const content = (
          <>
            <strong><bdi dir="ltr">{row.note_label}</bdi></strong>
            <span>{row.has_data === false ? t('heatmap.noData') : <bdi dir="ltr">{formatNumber(Math.round(row.avg_signed_cents))}c</bdi>}</span>
          </>
        );
        if (!onSelect) {
          return (
            <div
              className={`heat-cell readonly ${row.severity_color ?? 'insufficient'}`}
              key={row.note_label}
              title={`${row.note_label}: ${detail}`}
              aria-label={`${row.note_label}: ${detail}`}
              role="img"
            >
              {content}
            </div>
          );
        }
        return (
          <button
            className={`heat-cell ${row.severity_color ?? 'insufficient'} ${selectedNote === row.note_label ? 'selected' : ''}`}
            key={row.note_label}
            title={`${row.note_label}: ${detail}`}
            aria-label={`${row.note_label}: ${detail}`}
            aria-pressed={selectedNote === row.note_label}
            onClick={() => onSelect?.(row)}
            type="button"
          >
            {content}
          </button>
        );
      })}
    </div>
  );
}
