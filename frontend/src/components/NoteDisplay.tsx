import type { PitchFrame } from '../domain/types';
import { describeCents } from '../domain/tuningLanguage';
import { useThrottledAnnouncement } from '../hooks/useThrottledAnnouncement';
import { useI18n } from '../i18n/LocaleContext';

/**
 * The single, unmissable tuner readout: one big note name, a plain-language
 * verdict ("In tune" / "A little sharp"), and the cents number as a quiet
 * secondary detail. Concert pitch is available but de-emphasized.
 */
export function NoteDisplay({ frame }: { frame: PitchFrame | null }) {
  const { t, formatNumber } = useI18n();
  const hasPitch = Boolean(frame?.written_note_name) && frame?.tuning_status !== 'silence';
  const note = hasPitch ? `${frame!.written_note_name}${frame!.written_octave}` : '—';
  const concert = frame?.concert_note_name ? `${frame.concert_note_name}${frame.concert_octave}` : null;
  const verdict = describeCents(hasPitch ? frame?.cents_deviation : null);
  const verdictLabel = verdict.tone === 'green'
    ? t('tuning.inTune')
    : verdict.direction === 'sharp'
      ? t(verdict.tone === 'amber' ? 'tuning.littleSharp' : 'tuning.sharp')
      : verdict.direction === 'flat'
        ? t(verdict.tone === 'amber' ? 'tuning.littleFlat' : 'tuning.flat')
        : t('tuning.playNote');
  const detail = hasPitch && verdict.direction !== 'center' && frame?.cents_deviation != null
    ? t(verdict.direction === 'sharp' ? 'tuning.centsSharp' : 'tuning.centsFlat', { cents: formatNumber(Math.abs(Math.round(frame.cents_deviation))) })
    : hasPitch ? t('tuning.rightOn') : '';
  const visualLabel = hasPitch ? t('tuning.noteVerdict', { note, verdict: verdictLabel }) : t('tuning.playNote');
  const announcement = useThrottledAnnouncement(visualLabel);

  return (
    <section
      className={`note-display tone-${verdict.tone}`}
      aria-label={visualLabel}
    >
      <strong className="note-display-note"><bdi dir="ltr">{note}</bdi></strong>
      <span className={`note-display-verdict tone-${verdict.tone}`}>{hasPitch ? verdictLabel : t('tuning.playNote')}</span>
      {hasPitch && detail && <span className="note-display-detail"><bdi>{detail}</bdi></span>}
      {hasPitch && concert && <span className="note-display-concert">{t('tuning.concert')} <bdi dir="ltr">{concert}</bdi></span>}
      <span className="visually-hidden" role="status" aria-live="polite" aria-atomic="true">{announcement}</span>
    </section>
  );
}
