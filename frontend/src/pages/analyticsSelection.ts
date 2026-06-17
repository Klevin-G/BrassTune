import type { NoteStats } from '../domain/types';

export function measuredRows(rows: NoteStats[]) {
  return rows.filter((row) => row.has_data !== false && row.event_count > 0);
}

export function selectDefaultNoteLabel(rows: NoteStats[], selectedNote?: string) {
  if (rows.length === 0) return undefined;
  if (selectedNote && rows.some((row) => row.note_label === selectedNote)) {
    return selectedNote;
  }
  const worstMeasured = measuredRows(rows).sort((a, b) => b.problem_severity - a.problem_severity)[0];
  return worstMeasured?.note_label ?? rows[0]?.note_label;
}
