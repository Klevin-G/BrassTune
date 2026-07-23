import { Circle, Mic, Square, Timer } from 'lucide-react';
import { useThrottledAnnouncement } from '../hooks/useThrottledAnnouncement';
import { useI18n } from '../i18n/LocaleContext';

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
  const { t, formatNumber } = useI18n();
  const minutes = Math.floor(elapsedSeconds / 60);
  const seconds = String(elapsedSeconds % 60).padStart(2, '0');
  const actionLabel = busy ? t(recording ? 'session.savingTake' : 'session.startingTake') : t(recording ? 'session.stopAndSave' : 'session.saveTake');
  const actionText = busy ? t(recording ? 'session.saving' : 'session.starting') : t(recording ? 'session.stopSave' : 'session.saveTake');
  const timerLabel = t('session.timer', { minutes: formatNumber(minutes), seconds: formatNumber(Number(seconds)) });
  const timerAnnouncement = useThrottledAnnouncement(
    recording ? timerLabel : t('session.stopped'),
    15_000,
  );
  return (
    <div className="session-controls">
      <button className={`${recording ? 'primary-button' : 'ghost-button'} icon-first-action`} aria-label={actionLabel} aria-busy={busy || undefined} disabled={busy} onClick={recording ? onStop : onStart} type="button">
        {recording ? <Square size={18} /> : <Circle size={18} />}
        <span>{actionText}</span>
      </button>
      {!demoMode && onMicStop && micActive === false && (
        <button className="ghost-button icon-first-action" aria-label={t('session.turnOnMic')} onClick={onMicStart} type="button">
          <Mic size={18} />
          <span>{microphoneLabel ?? t('session.turnOnMicShort')}</span>
        </button>
      )}
      {recording && (
        <div className="timer-chip" role="timer" aria-label={timerLabel}>
          <Timer size={17} />
          {minutes}:{seconds}
        </div>
      )}
      <span className="visually-hidden" role="status" aria-live="polite" aria-atomic="true">{timerAnnouncement}</span>
    </div>
  );
}
