import { Pause, Play, RotateCcw } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { GUIDED_WARMUP_SECONDS, GUIDED_WARMUP_STEPS, warmupStepAt } from '../../domain/warmup';
import { usePracticeLibrary } from '../../state/PracticeLibraryContext';
import { SectionCard } from '../ui/AppPrimitives';

export function GuidedWarmupPanel() {
  const { library, setWarmupProgress, recordRecent, recordActivity } = usePracticeLibrary();
  const [elapsed, setElapsed] = useState(library.warmup.elapsedSeconds);
  const [running, setRunning] = useState(false);
  const completionRecordedRef = useRef(elapsed >= GUIDED_WARMUP_SECONDS);
  const position = warmupStepAt(elapsed);
  const step = GUIDED_WARMUP_STEPS[position.index];
  const complete = elapsed >= GUIDED_WARMUP_SECONDS;

  useEffect(() => {
    if (running) return;
    setElapsed(library.warmup.elapsedSeconds);
  }, [library.warmup.elapsedSeconds, running]);

  useEffect(() => {
    if (!running) return undefined;
    const timer = window.setInterval(() => {
      setElapsed((current) => Math.min(GUIDED_WARMUP_SECONDS, current + 1));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [running]);

  useEffect(() => {
    setWarmupProgress({ elapsedSeconds: elapsed, stepIndex: position.index });
    if (elapsed >= GUIDED_WARMUP_SECONDS) {
      setRunning(false);
      if (!completionRecordedRef.current) {
        completionRecordedRef.current = true;
        recordActivity(5);
      }
    }
  }, [elapsed, position.index, recordActivity, setWarmupProgress]);

  const start = () => {
    if (complete) {
      completionRecordedRef.current = false;
      setElapsed(0);
    }
    recordRecent({ kind: 'warmup', id: 'guided-5', label: '5-minute warm-up', href: '/practice#warmup' });
    setRunning(true);
  };

  const reset = () => {
    setRunning(false);
    completionRecordedRef.current = false;
    setElapsed(0);
  };

  const remaining = Math.max(0, GUIDED_WARMUP_SECONDS - elapsed);
  return (
    <SectionCard title="Guided 5-minute warm-up" eyebrow="Resumes on this device" action={<span className="practice-time">{Math.floor(remaining / 60)}:{String(remaining % 60).padStart(2, '0')}</span>}>
      <div id="warmup" className="practice-feature-stack">
        <p className="practice-lead"><strong>{complete ? 'Warm-up complete' : `${position.index + 1}. ${step.title}`}</strong></p>
        <p>{complete ? 'Nice work. You can repeat it now or come back tomorrow.' : step.instruction}</p>
        <progress max={GUIDED_WARMUP_SECONDS} value={elapsed} aria-label={`${elapsed} of ${GUIDED_WARMUP_SECONDS} warm-up seconds`} />
        <div className="practice-actions">
          <button className="primary-button" type="button" onClick={running ? () => setRunning(false) : start}>
            {running ? <Pause size={18} /> : <Play size={18} />}
            {running ? 'Pause' : elapsed > 0 && !complete ? 'Resume' : complete ? 'Repeat' : 'Start warm-up'}
          </button>
          {elapsed > 0 && <button className="ghost-button" type="button" onClick={reset}><RotateCcw size={17} />Reset</button>}
        </div>
      </div>
    </SectionCard>
  );
}
