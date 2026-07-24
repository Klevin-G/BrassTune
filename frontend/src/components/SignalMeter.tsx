import { describeSaveEligibility } from '../domain/pitchFrameStatus';
import type { PitchFrame } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

export function SignalMeter({ frame }: { frame: PitchFrame | null }) {
  const { t, formatNumber } = useI18n();
  const eligibility = describeSaveEligibility(frame);
  const hasPitchLock = eligibility.canSave;
  const confidence = hasPitchLock ? Math.max(95, Math.round((frame?.confidence ?? 0) * 100)) : 0;
  const rms = Math.min(100, Math.round((frame?.rms ?? 0) * 1000));
  return (
    <div className="signal-meter">
      <div>
        <span>{t(`signal.${eligibility.code}` as MessageId)}</span>
        <strong><bdi dir="ltr">{hasPitchLock ? `${formatNumber(confidence)}%` : t('signal.noLock')}</bdi></strong>
      </div>
      <meter min={0} max={100} value={confidence} aria-label={t('signal.confidence')} />
      <div>
        <span>{t('signal.level')}</span>
        <strong><bdi dir="ltr">{formatNumber(rms)}%</bdi></strong>
      </div>
      <meter min={0} max={100} value={rms} aria-label={t('signal.inputLevel')} />
    </div>
  );
}
