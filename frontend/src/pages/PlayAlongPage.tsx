import { AlertCircle, Mic, Music4, Play, RotateCcw, SkipForward, Square, Star, Trophy, Volume2 } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import './PlayAlongPage.css';
import { PageHeader, ScreenContainer, SectionCard, SelectionChip } from '../components/ui/AppPrimitives';
import { usePitchStream } from '../hooks/usePitchStream';
import {
  EXERCISES,
  MAJOR_SCALES,
  MINOR_SCALES,
  OTHER_EXERCISES,
  PlayAlongGrader,
  samePitchClass,
  summarizeGrades,
  type Exercise,
  type GraderSnapshot,
  type NoteGrade,
  type CentsGrade,
} from '../domain/playAlong';
import { describeCents, describeInTunePercent, starsForPercent } from '../domain/tuningLanguage';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { midiToFrequency, noteLabelToMidi } from '../domain/music';
import { useAppSettings } from '../state/AppSettingsContext';

type Phase = 'idle' | 'running' | 'done';

const GRADE_TONE: Record<string, string> = {
  excellent: 'tone-green',
  good: 'tone-teal',
  close: 'tone-amber',
  off: 'tone-red',
  missed: 'tone-muted',
};

// Plain word for each note's landing, so results lead with language not cents.
const GRADE_WORD: Record<CentsGrade, string> = {
  excellent: 'Spot on',
  good: 'In tune',
  close: 'A little off',
  off: 'Off',
  missed: 'Skipped',
};

// Difficulty flag + one-line plain-English help per exercise, so a beginner
// knows where to start and what an unfamiliar term means.
type Difficulty = { tag: string; variant: 'start' | 'plain' | 'hard' };
const EXERCISE_META: Record<string, { difficulty: Difficulty; help: string }> = {
  cmaj: { difficulty: { tag: 'Start here', variant: 'start' }, help: 'The easiest place to begin — eight notes going up.' },
  fmaj: { difficulty: { tag: 'Easy', variant: 'plain' }, help: 'Same idea as C major, starting on F.' },
  gmaj: { difficulty: { tag: 'Easy', variant: 'plain' }, help: 'Same idea as C major, starting on G.' },
  arpeggio: { difficulty: { tag: 'Easy', variant: 'plain' }, help: 'Just the main notes of the chord — skips in between.' },
  chromatic: { difficulty: { tag: 'Harder', variant: 'hard' }, help: 'Every half-step in a row. Trickier — try it once scales feel easy.' },
  longtones: { difficulty: { tag: 'Warm-up', variant: 'plain' }, help: 'Hold each note long and steady to warm up.' },
};

function exerciseMeta(exercise: Exercise): { difficulty: Difficulty; help: string } {
  const explicit = EXERCISE_META[exercise.id];
  if (explicit) return explicit;
  if (exercise.group === 'major') {
    return { difficulty: { tag: 'Major', variant: 'plain' }, help: `Play the ${exercise.label} scale going up.` };
  }
  return { difficulty: { tag: 'Minor', variant: 'plain' }, help: `Play the ${exercise.label} scale going up (natural minor).` };
}

// Written -> concert transposition (semitones down) for the reference tone, so
// "Hear it" sounds the pitch the player should actually produce on their horn.
const WRITTEN_TRANSPOSE: Record<string, number> = {
  trumpet: 2,
  cornet: 2,
  flugelhorn: 2,
  baritone: 2,
  horn: 7,
  'french-horn': 7,
  trombone: 0,
  'bass-trombone': 0,
  euphonium: 0,
  tuba: 0,
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

function verdictHeadline(stars: number): string {
  if (stars >= 3) return 'Nailed it!';
  if (stars === 2) return 'Great playing!';
  if (stars === 1) return 'Nice work!';
  return 'Good try — keep at it!';
}

function bestKey(exerciseId: string): string {
  return `brasstune.playalong.best.${exerciseId}`;
}

function readBest(exerciseId: string): number | null {
  try {
    const raw = localStorage.getItem(bestKey(exerciseId));
    if (raw == null) return null;
    const value = Number(raw);
    return Number.isFinite(value) ? value : null;
  } catch {
    return null;
  }
}

function writeBest(exerciseId: string, percent: number): void {
  try {
    localStorage.setItem(bestKey(exerciseId), String(percent));
  } catch {
    /* storage unavailable — best is a nicety, safe to skip */
  }
}

export function PlayAlongPage() {
  const { instrumentId, referencePitch } = useAppSettings();
  const [exerciseId, setExerciseId] = useState(EXERCISES[0].id);
  const [phase, setPhase] = useState<Phase>('idle');
  const [snapshot, setSnapshot] = useState<GraderSnapshot | null>(null);
  const [error, setError] = useState('');
  const [prevBest, setPrevBest] = useState<number | null>(null);
  const [isNewBest, setIsNewBest] = useState(false);

  const graderRef = useRef<PlayAlongGrader | null>(null);
  const phaseRef = useRef<Phase>('idle');
  const finishRef = useRef<() => void>(() => {});
  const mountedRef = useRef(true);
  const exerciseIdRef = useRef(exerciseId);
  const audioCtxRef = useRef<AudioContext | null>(null);
  phaseRef.current = phase;
  exerciseIdRef.current = exerciseId;

  const exercise = EXERCISES.find((item) => item.id === exerciseId) ?? EXERCISES[0];
  const meta = exerciseMeta(exercise);

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

  const recordBest = useCallback((finalResults: NoteGrade[]) => {
    const summary = summarizeGrades(finalResults);
    const previous = readBest(exerciseIdRef.current);
    setPrevBest(previous);
    const beat = previous == null || summary.inTunePercent > previous;
    setIsNewBest(beat);
    if (beat) writeBest(exerciseIdRef.current, summary.inTunePercent);
  }, []);

  finishRef.current = () => {
    setPhase('done');
    stream.stopMicrophone();
    recordBest(graderRef.current?.results ?? []);
  };

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      stream.stopMicrophone();
    };
  }, []); // stop mic on unmount

  useEffect(() => () => {
    audioCtxRef.current?.close().catch(() => undefined);
  }, []); // release the reference-tone audio context on unmount

  // Play the concert pitch of a written note as a short reference tone.
  const hearNote = useCallback(
    (writtenNote: string) => {
      const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioContextClass) return;
      let ctx = audioCtxRef.current;
      if (!ctx) {
        ctx = new AudioContextClass();
        audioCtxRef.current = ctx;
      }
      if (ctx.state === 'suspended') void ctx.resume();

      const writtenMidi = noteLabelToMidi(`${writtenNote}4`);
      const semitones = WRITTEN_TRANSPOSE[instrumentId] ?? 0;
      const frequency = midiToFrequency(writtenMidi - semitones, referencePitch);

      const now = ctx.currentTime;
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = frequency;
      gain.gain.setValueAtTime(0.0001, now);
      gain.gain.exponentialRampToValueAtTime(0.22, now + 0.04);
      gain.gain.setValueAtTime(0.22, now + 1.0);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 1.35);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 1.4);
    },
    [instrumentId, referencePitch],
  );

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
      setError('We couldn’t turn on your microphone. Allow mic access in your browser (look for the mic icon in the address bar), then tap Start again.');
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
  const stars = summary ? starsForPercent(summary.inTunePercent) : 0;
  const percentVerdict = summary ? describeInTunePercent(summary.inTunePercent) : null;

  const noteStatus = (index: number): 'done' | 'current' | 'upcoming' => {
    if (index < (snapshot?.index ?? 0)) return 'done';
    if (index === (snapshot?.index ?? 0) && phase === 'running') return 'current';
    return 'upcoming';
  };

  const bestLine = (() => {
    if (!summary) return null;
    if (isNewBest) {
      return prevBest == null ? 'First time through — nice start!' : `New best! You beat ${prevBest}% in tune.`;
    }
    if (prevBest != null) {
      const gap = prevBest - summary.inTunePercent;
      return gap === 0 ? `Tied your best of ${prevBest}% in tune.` : `Your best is ${prevBest}% in tune — ${gap}% to beat it.`;
    }
    return null;
  })();

  return (
    <ScreenContainer>
      <PageHeader
        title="Play-Along"
        description="Pick an exercise and play it. We’ll listen and tell you how in-tune each note is."
      />

      {phase === 'idle' && (
        <SectionCard title="Choose an exercise">
          <div className="pa-exercise-groups">
            {([
              ['Major scales', MAJOR_SCALES],
              ['Minor scales', MINOR_SCALES],
              ['Other exercises', OTHER_EXERCISES],
            ] as const).map(([heading, exercises]) => (
              <section className="pa-exercise-group" aria-labelledby={`pa-${heading.replace(/ /g, '-').toLowerCase()}`} key={heading}>
                <h3 id={`pa-${heading.replace(/ /g, '-').toLowerCase()}`}>{heading}</h3>
                <div className="chip-row pa-chips">
                  {exercises.map((item) => {
                    const itemMeta = exerciseMeta(item);
                    return (
                      <SelectionChip
                        key={item.id}
                        active={item.id === exerciseId}
                        onClick={() => setExerciseId(item.id)}
                        tone="gold"
                      >
                        <span className="pa-chip-body">
                          {item.label}
                          {item.id === 'cmaj' && <span className={`pa-chip-tag pa-tag-${itemMeta.difficulty.variant}`}>{itemMeta.difficulty.tag}</span>}
                        </span>
                      </SelectionChip>
                    );
                  })}
                </div>
              </section>
            ))}
          </div>

          <div className="pa-selected">
            <div className="pa-selected-info">
              <p className="pa-selected-detail">
                {exercise.detail.replace('ascending', 'going up')} · {exercise.notes.length} notes · shown for your {instrumentDisplayName(instrumentId)}
              </p>
              {meta && <p className="pa-selected-help">{meta.help}</p>}
            </div>
            <button className="ghost-button pa-hear" type="button" onClick={() => hearNote(exercise.notes[0])}>
              <Volume2 size={17} />
              Hear it
            </button>
          </div>

          <button className="primary-button pa-start" type="button" onClick={start}>
            <Play size={20} />
            Start
          </button>
          <p className="pa-mic-note">
            <Mic size={15} />
            We’ll ask to use your microphone so we can hear you play.
          </p>
          {error && (
            <p className="pa-error" role="status" aria-live="polite">
              <AlertCircle size={16} />
              {error}
            </p>
          )}
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
              <strong className={samePitchClass(snapshot.detectedName, snapshot.currentName) ? 'match' : ''}>{snapshot.detectedName ?? '—'}</strong>
              {(() => {
                const cents = snapshot.detectedCents;
                const onTarget = samePitchClass(snapshot.detectedName, snapshot.currentName) && cents != null;
                if (!onTarget) {
                  return (
                    <span className="pa-live-verdict">
                      {snapshot.detectedName ? `Play ${snapshot.currentName}` : 'Listening…'}
                    </span>
                  );
                }
                const verdict = describeCents(cents);
                return (
                  <span className={`pa-live-verdict tone-${verdict.tone}`}>
                    {verdict.label}
                    {verdict.cue ? ` — ${verdict.cue}` : ''}
                    {verdict.tone !== 'green' && verdict.detail ? <em className="pa-live-cents"> ({verdict.detail})</em> : null}
                  </span>
                );
              })()}
            </div>
          </div>
          <p className="pa-hold-caption">
            <Mic size={15} />
            Hold each note steady until it locks in.
          </p>
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
            <button className="ghost-button" type="button" onClick={() => snapshot.currentName && hearNote(snapshot.currentName)}>
              <Volume2 size={17} />
              Hear it
            </button>
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

      {phase === 'done' && summary && percentVerdict && (
        <SectionCard title="Your score">
          <div className="pa-verdict">
            <div className="pa-stars" role="img" aria-label={`${stars} out of 3 stars`}>
              {[0, 1, 2].map((i) => (
                <Star key={i} size={36} className={i < stars ? 'pa-star on' : 'pa-star'} fill={i < stars ? 'currentColor' : 'none'} />
              ))}
            </div>
            <strong className={`pa-verdict-title tone-${percentVerdict.tone}`}>{verdictHeadline(stars)}</strong>
            <p className="pa-verdict-sub">{percentVerdict.label} · {summary.inTune} of {summary.total} notes on pitch</p>
            {bestLine && (
              <p className={`pa-best ${isNewBest ? 'pa-best-new' : ''}`}>
                <Trophy size={15} />
                {bestLine}
              </p>
            )}
          </div>

          <div className="settings-actions">
            <button className="primary-button" type="button" onClick={start}>
              <RotateCcw size={18} />
              Play again
            </button>
            <button className="ghost-button" type="button" onClick={stop}>
              <Music4 size={18} />
              Pick another
            </button>
          </div>

          <details className="pa-details">
            <summary>Note by note</summary>
            <div className="playalong-results">
              {results.map((grade: NoteGrade, index: number) => (
                <div className={`playalong-result-row ${GRADE_TONE[grade.grade]}`} key={index}>
                  <span className="playalong-result-note">{grade.name}</span>
                  <span className="playalong-result-grade">
                    <span className="pa-grade-word">{GRADE_WORD[grade.grade]}</span>
                    {grade.grade !== 'missed' && grade.avgCents != null && (
                      <span className="pa-grade-cents">{grade.avgCents > 0 ? '+' : ''}{grade.avgCents}¢</span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </details>
        </SectionCard>
      )}
    </ScreenContainer>
  );
}
