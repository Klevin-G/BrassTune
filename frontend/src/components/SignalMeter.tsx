import { describeSaveEligibility } from '../domain/pitchFrameStatus';
import type { PitchFrame } from '../domain/types';

export function SignalMeter({ frame }: { frame: PitchFrame | null }) {
  const eligibility = describeSaveEligibility(frame);
  const hasPitchLock = eligibility.canSave;
  const confidence = hasPitchLock ? Math.max(95, Math.round((frame?.confidence ?? 0) * 100)) : 0;
  const rms = Math.min(100, Math.round((frame?.rms ?? 0) * 1000));
  return (
    <div className="signal-meter">
      <div>
        <span>{eligibility.label}</span>
        <strong>{hasPitchLock ? `${confidence}%` : 'No lock'}</strong>
      </div>
      <meter min={0} max={100} value={confidence} aria-label="Pitch confidence percentage" />
      <div>
        <span>Signal</span>
        <strong>{rms}%</strong>
      </div>
      <meter min={0} max={100} value={rms} aria-label="Input signal level percentage" />
    </div>
  );
}
