import { describe, expect, it } from 'vitest';
import type { NoteStats } from '../domain/types';
import { selectDefaultNoteLabel } from './analyticsSelection';

function note(partial: Partial<NoteStats> & Pick<NoteStats, 'note_label'>): NoteStats {
  return {
    written_note: partial.note_label.replace(/[0-9]/g, ''),
    written_octave: Number(partial.note_label.replace(/[^0-9]/g, '')) || 4,
    note_label: partial.note_label,
    avg_signed_cents: 0,
    avg_abs_cents: 0,
    median_cents: 0,
    stddev_cents: 0,
    in_tune_percentage: 0,
    duration_ms: 0,
    duration_seconds: 0,
    sample_count: 0,
    event_count: partial.event_count ?? 1,
    stability_score: 0,
    trend: 'centered',
    severity: 'ok',
    problem_severity: partial.problem_severity ?? 0,
    has_data: partial.has_data,
    severity_color: partial.severity_color,
    recommendation_summary: partial.recommendation_summary,
  };
}

describe('selectDefaultNoteLabel', () => {
  it('keeps the selected note when it still exists', () => {
    const rows = [note({ note_label: 'G4', problem_severity: 4 }), note({ note_label: 'D5', problem_severity: 20 })];
    expect(selectDefaultNoteLabel(rows, 'G4')).toBe('G4');
  });

  it('falls back to the worst measured note when selection disappears', () => {
    const rows = [note({ note_label: 'G4', problem_severity: 4 }), note({ note_label: 'D5', problem_severity: 20 })];
    expect(selectDefaultNoteLabel(rows, 'C6')).toBe('D5');
  });

  it('uses the first full-range cell when no note has enough data', () => {
    const rows = [note({ note_label: 'F#3', has_data: false, event_count: 0 }), note({ note_label: 'G3', has_data: false, event_count: 0 })];
    expect(selectDefaultNoteLabel(rows)).toBe('F#3');
  });
});
