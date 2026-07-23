import type { PitchFrame } from '../domain/types';
import { describeCents } from '../domain/tuningLanguage';
import { useI18n } from '../i18n/LocaleContext';

const RANGE = 50; // cents shown to each side of center

/**
 * One large horizontal tuning strip: a flat←0→sharp scale with a single moving
 * indicator that travels over the same scale it measures, a bold green center
 * "in tune" zone, and a reward glow that grows the longer you hold centered.
 */
export function TuningMeter({ frame, holdFraction = 0 }: { frame: PitchFrame | null; holdFraction?: number }) {
  const { t, formatNumber } = useI18n();
  const hasPitch = frame != null && frame.cents_deviation != null && frame.tuning_status !== 'silence';
  const cents = hasPitch ? Math.max(-RANGE, Math.min(RANGE, frame!.cents_deviation!)) : 0;
  const verdict = describeCents(hasPitch ? frame!.cents_deviation : null);
  const pct = 50 + (cents / RANGE) * 50; // 0..100 across the strip
  const centered = verdict.direction === 'center';
  const verdictLabel = verdict.tone === 'green'
    ? t('tuning.inTune')
    : verdict.direction === 'sharp'
      ? t(verdict.tone === 'amber' ? 'tuning.littleSharp' : 'tuning.sharp')
      : verdict.direction === 'flat'
        ? t(verdict.tone === 'amber' ? 'tuning.littleFlat' : 'tuning.flat')
        : t('tuning.noNote');

  return (
    <div
      className={`tuning-meter tone-${verdict.tone}${hasPitch ? ' active' : ''}${centered ? ' centered' : ''}`}
      role="meter"
      aria-label={t('tuning.meter')}
      aria-valuemin={-RANGE}
      aria-valuemax={RANGE}
      aria-valuenow={Math.round(cents)}
      aria-valuetext={hasPitch ? t('tuning.meterValue', { verdict: verdictLabel, cents: formatNumber(Math.round(cents)) }) : t('tuning.noNote')}
    >
      <div className="tuning-meter-labels">
        <span dir="auto">{t('tuning.flat')}</span>
        <span dir="auto">{t('tuning.inTune')}</span>
        <span dir="auto">{t('tuning.sharp')}</span>
      </div>
      <div className="tuning-meter-track">
        <span className="tuning-meter-zone tuning-meter-zone-center" />
        <span className="tuning-meter-tick" style={{ left: '50%' }} />
        {hasPitch && (
          <span
            className="tuning-meter-reward"
            style={{ opacity: centered ? 0.15 + holdFraction * 0.55 : 0, transform: `translate(-50%,-50%) scale(${0.6 + holdFraction * 0.9})` }}
          />
        )}
        <span className="tuning-meter-indicator" style={{ left: `${pct}%` }} />
      </div>
    </div>
  );
}
