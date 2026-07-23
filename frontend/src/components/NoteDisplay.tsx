import type { PitchFrame } from '../domain/types';
import { describeCents } from '../domain/tuningLanguage';
import { useThrottledAnnouncement } from '../hooks/useThrottledAnnouncement';

/**
 * The single, unmissable tuner readout: one big note name, a plain-language
 * verdict ("In tune" / "A little sharp"), and the cents number as a quiet
 * secondary detail. Concert pitch is available but de-emphasized.
 */
export function NoteDisplay({ frame }: { frame: PitchFrame | null }) {
  const hasPitch = Boolean(frame?.written_note_name) && frame?.tuning_status !== 'silence';
  const note = hasPitch ? `${frame!.written_note_name}${frame!.written_octave}` : '—';
  const concert = frame?.concert_note_name ? `${frame.concert_note_name}${frame.concert_octave}` : null;
  const verdict = describeCents(hasPitch ? frame?.cents_deviation : null);
  const visualLabel = hasPitch ? `${note}, ${verdict.label}` : 'Play a note';
  const announcement = useThrottledAnnouncement(visualLabel);

  return (
    <section
      className={`note-display tone-${verdict.tone}`}
      aria-label={visualLabel}
    >
      <strong className="note-display-note">{note}</strong>
      <span className={`note-display-verdict tone-${verdict.tone}`}>{hasPitch ? verdict.label : 'Play a note'}</span>
      {hasPitch && verdict.detail && <span className="note-display-detail">{verdict.detail}</span>}
      {hasPitch && concert && <span className="note-display-concert">Concert {concert}</span>}
      <span className="visually-hidden" role="status" aria-live="polite" aria-atomic="true">{announcement}</span>
    </section>
  );
}
