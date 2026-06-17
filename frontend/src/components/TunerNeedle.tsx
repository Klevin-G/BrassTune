import type { PitchFrame } from '../domain/types';

export function TunerNeedle({ frame }: { frame: PitchFrame | null }) {
  const cents = frame?.cents_deviation ?? 0;
  const clamped = Math.max(-50, Math.min(50, cents));
  const degrees = (clamped / 50) * 42;
  return (
    <div className="needle-panel" aria-label="Tuning needle">
      <div className="needle-scale">
        <span>-50</span>
        <span>Flat</span>
        <span>0</span>
        <span>Sharp</span>
        <span>+50</span>
      </div>
      <div className="needle-arc">
        <div className="needle-zone red left" />
        <div className="needle-zone yellow left" />
        <div className="needle-zone green" />
        <div className="needle-zone yellow right" />
        <div className="needle-zone red right" />
        <div className="needle" style={{ transform: `translateX(-50%) rotate(${degrees}deg)` }} />
      </div>
      <div className="needle-center" />
    </div>
  );
}

