import { Circle, Mic, Square, Timer } from 'lucide-react';

export function SessionControls({
  recording,
  elapsedSeconds,
  demoMode,
  micActive,
  onStart,
  onStop,
  onMicStart,
}: {
  recording: boolean;
  elapsedSeconds: number;
  demoMode: boolean;
  micActive: boolean;
  onStart: () => void;
  onStop: () => void;
  onMicStart: () => void;
}) {
  const minutes = Math.floor(elapsedSeconds / 60);
  const seconds = String(elapsedSeconds % 60).padStart(2, '0');
  return (
    <div className="session-controls">
      <button className="primary-button icon-first-action" aria-label={recording ? 'Stop recording' : 'Start recording'} onClick={recording ? onStop : onStart} type="button">
        {recording ? <Square size={18} /> : <Circle size={18} />}
        <span>{recording ? 'Stop' : 'Record'}</span>
      </button>
      {!demoMode && (
        <button className="ghost-button icon-first-action" aria-label={micActive ? 'Microphone is live' : 'Enable microphone'} onClick={onMicStart} disabled={micActive} type="button">
          <Mic size={18} />
          <span>{micActive ? 'Mic live' : 'Mic'}</span>
        </button>
      )}
      <div className="timer-chip" role="timer" aria-live="polite" aria-label={`Recording timer ${minutes} minutes ${seconds} seconds`}>
        <Timer size={17} />
        {minutes}:{seconds}
      </div>
    </div>
  );
}
