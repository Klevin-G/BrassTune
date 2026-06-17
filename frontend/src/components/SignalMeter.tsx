import { MIN_RECORDING_CONFIDENCE } from '../domain/music';
import type { PitchFrame } from '../domain/types';

export function SignalMeter({ frame }: { frame: PitchFrame | null }) {
  const hasPitchLock = Boolean(frame?.is_valid_for_recording && (frame.confidence ?? 0) >= MIN_RECORDING_CONFIDENCE);
  const confidence = hasPitchLock ? Math.max(95, Math.round((frame?.confidence ?? 0) * 100)) : 0;
  const rms = Math.min(100, Math.round((frame?.rms ?? 0) * 1000));
  return (
    <div className="signal-meter">
      <div>
        <span>Confidence</span>
        <strong>{hasPitchLock ? `${confidence}%` : 'No lock'}</strong>
      </div>
      <meter min={0} max={100} value={confidence} />
      <div>
        <span>Signal</span>
        <strong>{rms}%</strong>
      </div>
      <meter min={0} max={100} value={rms} />
    </div>
  );
}
