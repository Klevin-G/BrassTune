import { AlertCircle, Mic, Music4, Play, RotateCcw, SkipForward, Square, Star, Trophy, Volume2 } from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import './PlayAlongPage.css';
import { CustomExerciseBuilder } from '../components/practice/CustomExerciseBuilder';
import { PracticeReflectionCard } from '../components/practice/PracticeReflectionCard';
import { PageHeader, ScreenContainer, SectionCard, SelectionChip } from '../components/ui/AppPrimitives';
import { usePitchStream } from '../hooks/usePitchStream';
import {
  EXERCISES,
  DEFAULT_PLAY_ALONG_HOLD_MS,
  MAJOR_SCALES,
  MINOR_SCALES,
  OTHER_EXERCISES,
  PlayAlongGrader,
  samePitchClass,
  summarizeGrades,
  type Exercise,
  type GraderSnapshot,
  type NoteGrade,
} from '../domain/playAlong';
import { describeCents, describeInTunePercent, starsForPercent } from '../domain/tuningLanguage';
import { writtenNoteFrequency } from '../domain/referenceTone';
import { useAppSettings } from '../state/AppSettingsContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { ownerBestScorePrefix } from '../domain/practiceLibrary';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';

type Phase = 'idle' | 'running' | 'done';

export function canStartReferenceTone(phase: Phase, referenceToneActive: boolean): boolean {
  return phase !== 'running' && !referenceToneActive;
}

export function shouldGradePitchFrame(phase: Phase, referenceToneActive: boolean): boolean {
  return phase === 'running' && !referenceToneActive;
}

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

function bestKey(ownerId: string, exerciseId: string): string {
  return `${ownerBestScorePrefix(ownerId)}${exerciseId}`;
}

function readBest(ownerId: string | null, exerciseId: string): number | null {
  if (!ownerId) return null;
  try {
    const raw = localStorage.getItem(bestKey(ownerId, exerciseId));
    if (raw == null) return null;
    const value = Number(raw);
    return Number.isFinite(value) ? value : null;
  } catch {
    return null;
  }
}

function writeBest(ownerId: string | null, exerciseId: string, percent: number): void {
  if (!ownerId) return;
  try {
    localStorage.setItem(bestKey(ownerId, exerciseId), String(percent));
  } catch {
    /* storage unavailable — best is a nicety, safe to skip */
  }
}

export function PlayAlongPage() {
  const { t, formatNumber } = useI18n();
  const { instrumentId, referencePitch } = useAppSettings();
  const practiceLibrary = usePracticeLibrary();
  const [searchParams, setSearchParams] = useSearchParams();
  const allExercises: Exercise[] = [
    ...EXERCISES,
    ...practiceLibrary.library.customExercises.map((item) => ({ id: item.id, label: item.name, detail: t(item.source === 'generated' ? 'playAlong.generatedExercise' : 'playAlong.customExercise'), notes: item.notes, group: 'other' as const })),
  ];
  const requestedExerciseId = searchParams.get('exercise');
  const [exerciseId, setExerciseId] = useState(() => requestedExerciseId && allExercises.some((item) => item.id === requestedExerciseId) ? requestedExerciseId : EXERCISES[0].id);
  const [phase, setPhase] = useState<Phase>('idle');
  const [snapshot, setSnapshot] = useState<GraderSnapshot | null>(null);
  const [error, setError] = useState('');
  const [prevBest, setPrevBest] = useState<number | null>(null);
  const [isNewBest, setIsNewBest] = useState(false);

  const graderRef = useRef<PlayAlongGrader | null>(null);
  const phaseRef = useRef<Phase>('idle');
  const finishRef = useRef<() => void>(() => {});
  const mountedRef = useRef(true);
  const startInProgressRef = useRef(false);
  const startGenerationRef = useRef(0);
  const exerciseIdRef = useRef(exerciseId);
  const audioCtxRef = useRef<AudioContext | null>(null);
  const referenceToneOscillatorRef = useRef<OscillatorNode | null>(null);
  const referenceToneActiveRef = useRef(false);
  const [referenceToneActive, setReferenceToneActive] = useState(false);
  const completionRecordedRef = useRef(false);
  phaseRef.current = phase;
  exerciseIdRef.current = exerciseId;

  const exercise = allExercises.find((item) => item.id === exerciseId) ?? EXERCISES[0];
  const exerciseLabel = (item: Exercise): string => {
    if (practiceLibrary.library.customExercises.some((custom) => custom.id === item.id)) return item.label;
    const root = item.label.split(' ')[0];
    if (item.group === 'major') return t('playAlong.majorLabel', { note: root });
    if (item.group === 'minor') return t('playAlong.minorLabel', { note: root });
    if (item.id === 'arpeggio') return t('playAlong.arpeggioLabel');
    if (item.id === 'chromatic') return t('playAlong.chromaticLabel');
    return t('playAlong.longTonesLabel');
  };
  const localizedExerciseLabel = exerciseLabel(exercise);
  const exerciseHelp = (item: Exercise): string => {
    if (practiceLibrary.library.customExercises.some((custom) => custom.id === item.id)) return t('playAlong.helpCustom');
    if (item.id === 'cmaj') return t('playAlong.helpStart');
    if (item.id === 'fmaj') return t('playAlong.helpF');
    if (item.id === 'gmaj') return t('playAlong.helpG');
    if (item.id === 'arpeggio') return t('playAlong.helpArpeggio');
    if (item.id === 'chromatic') return t('playAlong.helpChromatic');
    if (item.id === 'longtones') return t('playAlong.helpLongTones');
    return t(item.group === 'major' ? 'playAlong.helpMajor' : 'playAlong.helpMinor', { exercise: exerciseLabel(item) });
  };
  const exerciseDetail = (item: Exercise): string => {
    if (practiceLibrary.library.customExercises.some((custom) => custom.id === item.id)) return item.detail;
    if (item.id === 'arpeggio') return 'C · E · G · C';
    if (item.id === 'chromatic') return t('playAlong.chromaticDetail');
    if (item.id === 'longtones') return t('playAlong.longTonesDetail');
    return t(item.group === 'minor' ? 'playAlong.minorDetail' : 'playAlong.exerciseDetail');
  };

  const onFrame = useCallback((frame: any) => {
    if (!shouldGradePitchFrame(phaseRef.current, referenceToneActiveRef.current) || !graderRef.current) return;
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
    const previous = readBest(practiceLibrary.ownerId, exerciseIdRef.current);
    setPrevBest(previous);
    const beat = previous == null || summary.inTunePercent > previous;
    setIsNewBest(beat);
    if (beat) writeBest(practiceLibrary.ownerId, exerciseIdRef.current, summary.inTunePercent);
  }, [practiceLibrary.ownerId]);

  finishRef.current = () => {
    setPhase('done');
    stream.stopMicrophone();
    recordBest(graderRef.current?.results ?? []);
    if (!completionRecordedRef.current) {
      completionRecordedRef.current = true;
      practiceLibrary.recordActivity(1);
    }
  };

  useEffect(() => {
    if (requestedExerciseId && allExercises.some((item) => item.id === requestedExerciseId)) setExerciseId(requestedExerciseId);
  }, [allExercises, requestedExerciseId]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      startGenerationRef.current += 1;
      startInProgressRef.current = false;
      stream.stopMicrophone();
    };
  }, []); // stop mic on unmount

  const stopReferenceTone = useCallback(() => {
    const oscillator = referenceToneOscillatorRef.current;
    referenceToneOscillatorRef.current = null;
    referenceToneActiveRef.current = false;
    setReferenceToneActive(false);
    if (!oscillator) return;
    oscillator.onended = null;
    try { oscillator.stop(); } catch { /* already stopped */ }
    oscillator.disconnect();
  }, []);

  useEffect(() => () => {
    const oscillator = referenceToneOscillatorRef.current;
    referenceToneOscillatorRef.current = null;
    referenceToneActiveRef.current = false;
    if (oscillator) {
      oscillator.onended = null;
      try { oscillator.stop(); } catch { /* already stopped */ }
      oscillator.disconnect();
    }
    audioCtxRef.current?.close().catch(() => undefined);
  }, []); // release the reference-tone audio context on unmount

  // Play the concert pitch of a written note as a short reference tone.
  const hearNote = useCallback(
    (writtenNote: string) => {
      if (!canStartReferenceTone(phaseRef.current, referenceToneActiveRef.current)) return;
      const AudioContextClass = window.AudioContext || (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AudioContextClass) return;
      let ctx = audioCtxRef.current;
      if (!ctx) {
        ctx = new AudioContextClass();
        audioCtxRef.current = ctx;
      }
      if (ctx.state === 'suspended') void ctx.resume();

      const frequency = writtenNoteFrequency(writtenNote, instrumentId, referencePitch);
      if (frequency == null) return;

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
      referenceToneActiveRef.current = true;
      referenceToneOscillatorRef.current = osc;
      setReferenceToneActive(true);
      osc.onended = () => {
        if (referenceToneOscillatorRef.current !== osc) return;
        referenceToneOscillatorRef.current = null;
        referenceToneActiveRef.current = false;
        setReferenceToneActive(false);
        osc.disconnect();
      };
      osc.start(now);
      osc.stop(now + 1.4);
    },
    [instrumentId, referencePitch],
  );

  const start = async () => {
    if (startInProgressRef.current || phaseRef.current === 'running') return;
    stopReferenceTone();
    startInProgressRef.current = true;
    const generation = ++startGenerationRef.current;
    setError('');
    completionRecordedRef.current = false;
    graderRef.current = new PlayAlongGrader(exercise.notes);
    setSnapshot(graderRef.current.snapshot());
    setPhase('running');
    try {
      const mic = await stream.startMicrophone();
      if (!mountedRef.current || generation !== startGenerationRef.current) {
        // Unmounted, stopped, or superseded while the permission dialog was open.
        stream.stopMicrophone();
        return;
      }
      if (!mic) {
        setPhase('idle');
        setError(t('playAlong.micError'));
      } else {
        practiceLibrary.recordRecent({ kind: 'play-along', id: exercise.id, label: localizedExerciseLabel, href: `/practice/play-along?exercise=${encodeURIComponent(exercise.id)}` });
      }
    } finally {
      if (generation === startGenerationRef.current) startInProgressRef.current = false;
    }
  };

  const stop = () => {
    startGenerationRef.current += 1;
    startInProgressRef.current = false;
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
      return prevBest == null ? t('playAlong.firstBest') : t('playAlong.newBest', { percent: formatNumber(prevBest) });
    }
    if (prevBest != null) {
      const gap = prevBest - summary.inTunePercent;
      return gap === 0 ? t('playAlong.tiedBest', { percent: formatNumber(prevBest) }) : t('playAlong.bestGap', { percent: formatNumber(prevBest), gap: formatNumber(gap) });
    }
    return null;
  })();

  const selectedTarget = { kind: 'play-along' as const, id: exercise.id, label: localizedExerciseLabel, href: `/practice/play-along?exercise=${encodeURIComponent(exercise.id)}` };
  const selectExercise = (id: string) => {
    setExerciseId(id);
    setSearchParams({ exercise: id }, { replace: true });
  };

  return (
    <ScreenContainer>
      <PageHeader
        title={t('playAlong.title')}
        description={t('playAlong.description')}
      />

      {phase === 'idle' && (
        <SectionCard title={t('playAlong.choose')}>
          <div className="pa-exercise-groups">
            {([
              ['major', t('playAlong.majorScales'), MAJOR_SCALES],
              ['minor', t('playAlong.minorScales'), MINOR_SCALES],
              ['other', t('playAlong.otherExercises'), OTHER_EXERCISES],
            ] as const).map(([groupId, heading, exercises]) => (
              <section className="pa-exercise-group" aria-labelledby={`pa-${groupId}`} key={groupId}>
                <h3 id={`pa-${groupId}`}>{heading}</h3>
                <div className="chip-row pa-chips">
                  {exercises.map((item) => {
                    return (
                      <SelectionChip
                        key={item.id}
                        active={item.id === exerciseId}
                        onClick={() => selectExercise(item.id)}
                        tone="gold"
                      >
                        <span className="pa-chip-body">
                          {exerciseLabel(item)}
                          {item.id === 'cmaj' && <span className="pa-chip-tag pa-tag-start">{t('playAlong.startHere')}</span>}
                        </span>
                      </SelectionChip>
                    );
                  })}
                </div>
              </section>
            ))}
            {practiceLibrary.library.customExercises.length > 0 && (
              <section className="pa-exercise-group" aria-labelledby="pa-saved-exercises">
                <h3 id="pa-saved-exercises">{t('playAlong.savedExercises')}</h3>
                <div className="chip-row pa-chips">
                  {practiceLibrary.library.customExercises.map((item) => (
                    <SelectionChip key={item.id} active={item.id === exerciseId} onClick={() => selectExercise(item.id)} tone="gold">{item.name}</SelectionChip>
                  ))}
                </div>
              </section>
            )}
          </div>

          <div className="pa-selected">
            <div className="pa-selected-info">
              <p className="pa-selected-detail">
                {exerciseDetail(exercise)} · {t('playAlong.noteCount', { count: exercise.notes.length })} · {t('playAlong.forInstrument', { instrument: t(`instrument.${instrumentId}` as MessageId) })}
              </p>
              <p className="pa-selected-help">{exerciseHelp(exercise)}</p>
            </div>
            <button className="ghost-button pa-hear" type="button" disabled={referenceToneActive} onClick={() => hearNote(exercise.notes[0])}>
              <Volume2 size={17} />
              {t('playAlong.hearIt')}
            </button>
            <button className="ghost-button" type="button" aria-pressed={practiceLibrary.isFavorite(selectedTarget)} onClick={() => practiceLibrary.toggleFavorite(selectedTarget)}>
              <Star size={17} fill={practiceLibrary.isFavorite(selectedTarget) ? 'currentColor' : 'none'} />
              {t(practiceLibrary.isFavorite(selectedTarget) ? 'playAlong.favorited' : 'playAlong.favorite')}
            </button>
          </div>

          <button className="primary-button pa-start" type="button" onClick={start}>
            <Play size={20} />
            {t('common.start')}
          </button>
          <p className="pa-mic-note">
            <Mic size={15} />
            {t('playAlong.micNote')}
          </p>
          {error && (
            <p className="pa-error" role="status" aria-live="polite">
              <AlertCircle size={16} />
              {error}
            </p>
          )}
          <CustomExerciseBuilder
            onSaved={selectExercise}
            onDeleted={(id) => {
              if (exerciseId === id) selectExercise(EXERCISES[0].id);
            }}
          />
        </SectionCard>
      )}

      {phase === 'running' && snapshot && (
        <SectionCard title={t('playAlong.play')} eyebrow={t('playAlong.noteProgress', { current: formatNumber(Math.min(snapshot.index + 1, exercise.notes.length)), total: formatNumber(exercise.notes.length) })}>
          <div className="playalong-live">
            <div className="playalong-target">
              <HoldRing fraction={snapshot.heldFraction} />
              <div className="playalong-target-note">
                <span className="playalong-target-label">{t('playAlong.playNote')}</span>
                <strong>{snapshot.currentName ?? '—'}</strong>
              </div>
            </div>
            <div className="playalong-detected">
              <span className="playalong-detected-label">{t('playAlong.youArePlaying')}</span>
              <strong className={samePitchClass(snapshot.detectedName, snapshot.currentName) ? 'match' : ''}>{snapshot.detectedName ?? '—'}</strong>
              {(() => {
                const cents = snapshot.detectedCents;
                const onTarget = samePitchClass(snapshot.detectedName, snapshot.currentName) && cents != null;
                if (!onTarget) {
                  return (
                    <span className="pa-live-verdict">
                      {snapshot.detectedName ? t('playAlong.playTarget', { note: snapshot.currentName ?? '' }) : t('playAlong.listening')}
                    </span>
                  );
                }
                const verdict = describeCents(cents);
                const label = verdict.tone === 'green' ? t('tuning.inTune') : verdict.direction === 'sharp' ? t(verdict.tone === 'amber' ? 'tuning.littleSharp' : 'tuning.sharp') : t(verdict.tone === 'amber' ? 'tuning.littleFlat' : 'tuning.flat');
                const cue = t(verdict.direction === 'sharp' ? 'tuning.easeDown' : verdict.direction === 'flat' ? 'tuning.liftUp' : 'tuning.holdIt');
                const detail = t(verdict.direction === 'sharp' ? 'tuning.centsSharp' : 'tuning.centsFlat', { cents: formatNumber(Math.abs(Math.round(cents))) });
                return (
                  <span className={`pa-live-verdict tone-${verdict.tone}`}>
                    {label} — {cue}
                    {verdict.tone !== 'green' ? <em className="pa-live-cents"> (<bdi>{detail}</bdi>)</em> : null}
                  </span>
                );
              })()}
            </div>
          </div>
          <p className="pa-hold-caption">
            <Mic size={15} />
            {t('playAlong.holdHelp', { seconds: formatNumber(DEFAULT_PLAY_ALONG_HOLD_MS / 1_000) })}
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
            <button className="ghost-button" type="button" disabled aria-disabled="true">
              <Volume2 size={17} />
              {t('playAlong.hearIt')}
            </button>
            <button className="ghost-button" type="button" onClick={skip}>
              <SkipForward size={17} />
              {t('playAlong.skipNote')}
            </button>
            <button className="ghost-button danger-action" type="button" onClick={stop}>
              <Square size={17} />
              {t('playAlong.stop')}
            </button>
          </div>
        </SectionCard>
      )}

      {phase === 'done' && summary && percentVerdict && (
        <>
        <SectionCard title={t('playAlong.score')}>
          <div className="pa-verdict">
            <div className="pa-stars" role="img" aria-label={t('playAlong.stars', { count: formatNumber(stars), total: formatNumber(3) })}>
              {[0, 1, 2].map((i) => (
                <Star key={i} size={36} className={i < stars ? 'pa-star on' : 'pa-star'} fill={i < stars ? 'currentColor' : 'none'} />
              ))}
            </div>
            <strong className={`pa-verdict-title tone-${percentVerdict.tone}`}>{t(stars >= 3 ? 'playAlong.verdictThree' : stars === 2 ? 'playAlong.verdictTwo' : stars === 1 ? 'playAlong.verdictOne' : 'playAlong.verdictTry')}</strong>
            <p className="pa-verdict-sub">{t('practice.percentInTune', { percent: formatNumber(summary.inTunePercent) })} · {t('playAlong.notesOnPitch', { inTune: formatNumber(summary.inTune), total: formatNumber(summary.total) })}</p>
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
              {t('playAlong.again')}
            </button>
            <button className="ghost-button" type="button" onClick={stop}>
              <Music4 size={18} />
              {t('playAlong.pickAnother')}
            </button>
          </div>

          <details className="pa-details">
            <summary>{t('playAlong.noteByNote')}</summary>
            <div className="playalong-results">
              {results.map((grade: NoteGrade, index: number) => (
                <div className={`playalong-result-row ${GRADE_TONE[grade.grade]}`} key={index}>
                  <span className="playalong-result-note">{grade.name}</span>
                  <span className="playalong-result-grade">
                    <span className="pa-grade-word">{t(`playAlong.grade.${grade.grade}` as MessageId)}</span>
                    {grade.grade !== 'missed' && grade.avgCents != null && (
                      <span className="pa-grade-cents">{grade.avgCents > 0 ? '+' : ''}{grade.avgCents}¢</span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          </details>
        </SectionCard>
        <PracticeReflectionCard />
        </>
      )}
    </ScreenContainer>
  );
}
