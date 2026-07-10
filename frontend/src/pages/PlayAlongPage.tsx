import { Check, Mic, Music4, RotateCcw, SkipForward, Square } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { PageHeader, ScreenContainer, SectionCard, SelectionChip } from '../components/ui/AppPrimitives';
import { usePitchStream } from '../hooks/usePitchStream';
import { EXERCISES, PlayAlongGrader, centsGrade, summarizeGrades, type GraderSnapshot, type NoteGrade } from '../domain/playAlong';
import { useAppSettings } from '../state/AppSettingsContext';

type Phase = 'idle' | 'running' | 'done';

const GRADE_TONE: Record<string, string> = {
  excellent: 'tone-green',
  good: 'tone-teal',
  close: 'tone-amber',
  off: 'tone-red',
  missed: 'tone-muted',
};

function HoldRing({ fraction }: { fraction: number }) {
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  return (
    <svg viewBox="0 0 120 120" className="playalong-ring" aria-hidden="true">
      <circle cx="60" cy="60" r={radius} className="playalong-ring-track" />
      <circle
        cx="60"
        cy="60"
        r={radius}
        className="playalong-ring-progress"
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - fraction)}
        transform="rotate(-90 60 60)"
      />
    </svg>
  );
}

export function PlayAlongPage() {
  const { instrumentId, referencePitch } = useAppSettings();
  const [exerciseId, setExerciseId] = useState(EXERCISES[0].id);
  const [phase, setPhase] = useState<Phase>('idle');
  const [snapshot, setSnapshot] = useState<GraderSnapshot | null>(null);
  const [error, setError] = useState('');

  const graderRef = useRef<PlayAlongGrader | null>(null);
  const phaseRef = useRef<Phase>('idle');
  const finishRef = useRef<() => void>(() => {});
  const mountedRef = useRef(true);
  phaseRef.current = phase;

  const exercise = EXERCISES.find((item) => item.id === exerciseId) ?? EXERCISES[0];

  const onFrame = useCallback((frame: any) => {
    if (phaseRef.current !== 'running' || !graderRef.current) return;
    const snap = graderRef.current.feed(frame, performance.now());
    setSnapshot(snap);
    if (snap.done) finishRef.current();
  }, []);

  const stream = usePitchStream({
    enabled: true,
    demoMode: false,
    instrumentId,
    referencePitch,
    recording: false,
    persistDemoFramesToBackend: false,
    onFrame,
  });

  finishRef.current = () => {
    setPhase('done');
    stream.stopMicrophone();
  };

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      stream.stopMicrophone();
    };
  }, []); // stop mic on unmount

  const start = async () => {
    setError('');
    graderRef.current = new PlayAlongGrader(exercise.notes);
    setSnapshot(graderRef.current.snapshot());
    setPhase('running');
    const mic = await stream.startMicrophone();
    if (!mountedRef.current) {
      // Unmounted (or navigated away) while the permission dialog was open.
      stream.stopMicrophone();
      return;
    }
    if (!mic) {
      setPhase('idle');
      setError('Microphone access is needed to grade your playing. Allow the mic and try again.');
    }
  };

  const stop = () => {
    setPhase('idle');
    setSnapshot(null);
    graderRef.current = null;
    stream.stopMicrophone();
  };

  const skip = () => {
    if (!graderRef.current) return;
    graderRef.current.skip();
    const snap = graderRef.current.snapshot();
    setSnapshot(snap);
    if (snap.done) finishRef.current();
  };

  const results = snapshot?.results ?? [];
  const summary = phase === 'done' ? summarizeGrades(results) : null;

  const noteStatus = (index: number): 'done' | 'current' | 'upcoming' => {
    if (index < (snapshot?.index ?? 0)) return 'done';
    if (index === (snapshot?.index ?? 0) && phase === 'running') return 'current';
    return 'upcoming';
  };

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Score practice"
        title="Play-Along Trainer"
        description="Pick an exercise, play it on your instrument, and BrassTune listens and grades each note in real time. Works with your microphone — no sheet music upload needed."
        meta={<Link className="ghost-button" to="/practice/score">Read sheet music →</Link>}
      />

      <SectionCard title="Choose an exercise" eyebrow="Written notes">
        <div className="chip-row">
          {EXERCISES.map((item) => (
            <SelectionChip
              key={item.id}
              active={item.id === exerciseId}
              onClick={() => phase !== 'running' && setExerciseId(item.id)}
              tone="gold"
            >
              {item.label}
            </SelectionChip>
          ))}
        </div>
        <p className="muted-copy">{exercise.detail} · {exercise.notes.length} notes · reads in your instrument’s pitch ({instrumentId})</p>
      </SectionCard>

      {phase === 'idle' && (
        <SectionCard title="Ready when you are" eyebrow="Self-paced">
          <p className="muted-copy">Play each highlighted note and hold it steady. When your pitch locks in, it’s scored and the trainer moves on. Go at your own pace.</p>
          <button className="primary-button" type="button" onClick={start}>
            <Mic size={18} />
            Start listening
          </button>
          {error && <p className="settings-status" role="status" aria-live="polite">{error}</p>}
        </SectionCard>
      )}

      {phase === 'running' && snapshot && (
        <SectionCard title="Play along" eyebrow={`Note ${Math.min(snapshot.index + 1, exercise.notes.length)} of ${exercise.notes.length}`}>
          <div className="playalong-live">
            <div className="playalong-target">
              <HoldRing fraction={snapshot.heldFraction} />
              <div className="playalong-target-note">
                <span className="playalong-target-label">Play</span>
                <strong>{snapshot.currentName ?? '—'}</strong>
              </div>
            </div>
            <div className="playalong-detected">
              <span className="playalong-detected-label">You’re playing</span>
              <strong className={snapshot.detectedName === snapshot.currentName ? 'match' : ''}>{snapshot.detectedName ?? '—'}</strong>
              {(() => {
                const cents = snapshot.detectedCents;
                const onTarget = snapshot.detectedName === snapshot.currentName && cents != null;
                if (!onTarget) {
                  return <span className="playalong-cents">{snapshot.detectedName ? `Move to ${snapshot.currentName}` : 'listening…'}</span>;
                }
                const rounded = Math.round(cents as number);
                if (Math.abs(rounded) <= 5) {
                  return <span className="playalong-cents locked">✓ Locked in — hold it</span>;
                }
                return (
                  <span className={`playalong-cents ${rounded > 0 ? 'sharp' : 'flat'}`}>
                    {rounded > 0 ? '▲' : '▼'} {Math.abs(rounded)}c {rounded > 0 ? 'sharp — ease down' : 'flat — lift up'}
                  </span>
                );
              })()}
              <span className="muted-copy">{stream.statusMessage}</span>
            </div>
          </div>
          <div className="playalong-sequence">
            {exercise.notes.map((note, index) => {
              const status = noteStatus(index);
              const graded = results[index];
              return (
                <span key={index} className={`playalong-note ${status} ${graded ? GRADE_TONE[graded.grade] : ''}`}>
                  {note}
                </span>
              );
            })}
          </div>
          <div className="settings-actions">
            <button className="ghost-button" type="button" onClick={skip}>
              <SkipForward size={17} />
              Skip note
            </button>
            <button className="ghost-button danger-action" type="button" onClick={stop}>
              <Square size={17} />
              Stop
            </button>
          </div>
        </SectionCard>
      )}

      {phase === 'done' && summary && (
        <>
          <SectionCard title="Your score" eyebrow={exercise.label}>
            <div className="metrics-grid">
              <article className="stat-card">
                <span>In tune</span>
                <strong>{summary.inTunePercent}%</strong>
                <p>{summary.inTune} of {summary.total} notes within 15¢</p>
              </article>
              <article className="stat-card">
                <span>Avg error</span>
                <strong>{summary.averageAbsCents != null ? `${summary.averageAbsCents}c` : '—'}</strong>
                <p>Across notes you played</p>
              </article>
              <article className="stat-card">
                <span>Notes played</span>
                <strong>{summary.hit}/{summary.total}</strong>
                <p>{summary.total - summary.hit} skipped</p>
              </article>
            </div>
            <div className="settings-actions">
              <button className="primary-button" type="button" onClick={start}>
                <RotateCcw size={18} />
                Play again
              </button>
              <button className="ghost-button" type="button" onClick={stop}>
                <Music4 size={18} />
                Pick another exercise
              </button>
            </div>
          </SectionCard>
          <SectionCard title="Note by note" eyebrow="How each note landed">
            <div className="playalong-results">
              {results.map((grade: NoteGrade, index: number) => (
                <div className={`playalong-result-row ${GRADE_TONE[grade.grade]}`} key={index}>
                  <span className="playalong-result-note">{grade.name}</span>
                  <span className="playalong-result-grade">
                    {grade.grade === 'missed' ? (
                      'Skipped'
                    ) : (
                      <>
                        {grade.grade === 'excellent' && <Check size={14} />}
                        {grade.avgCents != null ? `${grade.avgCents > 0 ? '+' : ''}${grade.avgCents}c` : ''} · {centsGrade(grade.avgCents)}
                      </>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </SectionCard>
        </>
      )}
    </ScreenContainer>
  );
}
