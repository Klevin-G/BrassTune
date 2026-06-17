import { Mic, Square, Timer, Video } from 'lucide-react';

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
      <button className="primary-button" onClick={recording ? onStop : onStart} type="button">
        {recording ? <Square size={18} /> : <Video size={18} />}
        {recording ? 'Stop recording' : 'Start recording'}
      </button>
      {!demoMode && (
        <button className="ghost-button" onClick={onMicStart} disabled={micActive} type="button">
          <Mic size={18} />
          {micActive ? 'Mic live' : 'Use microphone'}
        </button>
      )}
      <div className="timer-chip">
        <Timer size={17} />
        {minutes}:{seconds}
      </div>
    </div>
  );
}

