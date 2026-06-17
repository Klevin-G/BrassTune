import type { PitchFrame } from '../domain/types';

function signedCents(value: number | null | undefined) {
  if (value === null || value === undefined) return '--';
  return `${value > 0 ? '+' : ''}${Math.round(value)} cents`;
}

export function NoteDisplay({ frame }: { frame: PitchFrame | null }) {
  const note = frame?.written_note_name ? `${frame.written_note_name}${frame.written_octave}` : '--';
  const concert = frame?.concert_note_name ? `${frame.concert_note_name}${frame.concert_octave}` : '--';
  return (
    <section className={`note-display ${frame?.tuning_status ?? 'silence'}`}>
      <p>Written note</p>
      <strong>{note}</strong>
      <span>{signedCents(frame?.cents_deviation)}</span>
      <div className="note-meta">
        <span>Concert {concert}</span>
        <span>{frame?.frequency_hz ? `${frame.frequency_hz.toFixed(1)} Hz` : 'No clear pitch'}</span>
      </div>
    </section>
  );
}

