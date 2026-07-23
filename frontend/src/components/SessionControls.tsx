import { Circle, Mic, Square, Timer } from 'lucide-react';
import { useThrottledAnnouncement } from '../hooks/useThrottledAnnouncement';

export function SessionControls({
  recording,
  elapsedSeconds,
  demoMode,
  micActive,
  microphoneLabel,
  busy,
  onStart,
  onStop,
  onMicStart,
  onMicStop,
}: {
  recording: boolean;
  elapsedSeconds: number;
  demoMode: boolean;
  micActive: boolean;
  microphoneLabel?: string;
  busy?: boolean;
  onStart: () => void;
  onStop: () => void;
  onMicStart: () => void;
  onMicStop?: () => void;
}) {
  const minutes = Math.floor(elapsedSeconds / 60);
  const seconds = String(elapsedSeconds % 60).padStart(2, '0');
  const actionLabel = busy ? (recording ? 'Saving your take' : 'Starting your take') : recording ? 'Stop and save' : 'Save this take';
  const actionText = busy ? (recording ? 'Saving' : 'Starting') : recording ? 'Stop & save' : 'Save this take';
  const timerAnnouncement = useThrottledAnnouncement(
    recording ? `Recording timer ${minutes} minutes ${seconds} seconds` : 'Recording stopped',
    15_000,
  );
  return (
    <div className="session-controls">
      <button className={`${recording ? 'primary-button' : 'ghost-button'} icon-first-action`} aria-label={actionLabel} aria-busy={busy || undefined} disabled={busy} onClick={recording ? onStop : onStart} type="button">
        {recording ? <Square size={18} /> : <Circle size={18} />}
        <span>{actionText}</span>
      </button>
      {!demoMode && onMicStop && micActive === false && (
        <button className="ghost-button icon-first-action" aria-label="Turn on microphone" onClick={onMicStart} type="button">
          <Mic size={18} />
          <span>{microphoneLabel ?? 'Turn on mic'}</span>
        </button>
      )}
      {recording && (
        <div className="timer-chip" role="timer" aria-label={`Recording timer ${minutes} minutes ${seconds} seconds`}>
          <Timer size={17} />
          {minutes}:{seconds}
        </div>
      )}
      <span className="visually-hidden" role="status" aria-live="polite" aria-atomic="true">{timerAnnouncement}</span>
    </div>
  );
}
