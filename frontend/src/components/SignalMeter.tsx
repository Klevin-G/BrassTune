import type { PitchFrame } from '../domain/types';

export function SignalMeter({ frame }: { frame: PitchFrame | null }) {
  const confidence = Math.round((frame?.confidence ?? 0) * 100);
  const rms = Math.min(100, Math.round((frame?.rms ?? 0) * 1000));
  return (
    <div className="signal-meter">
      <div>
        <span>Confidence</span>
        <strong>{confidence}%</strong>
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

